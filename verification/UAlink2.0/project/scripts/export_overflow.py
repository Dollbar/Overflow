#!/usr/bin/env python3
"""Export one immutable source Git commit into owned Overflow partitions.

Run: python3 scripts/export_overflow.py --source PATH --commit FULL_COMMIT --dest ROOT --check
     python3 scripts/export_overflow.py --source PATH --commit FULL_COMMIT --dest ROOT
Outputs: ROOT/{rtl,verification,simulator}/UAlink2.0 and ownership manifest
verification/UAlink2.0/.ualink-export.json. --check only plans and validates; it writes nothing.
Next: review the destination Git diff, run exported checks from project, then publish separately.
"""
import argparse
import ast
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import tempfile

ROOT = (lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[1]))(__import__('pathlib').Path(__file__).resolve())
OWNER = 'ualink-overflow-export'
SCHEMA = 1
PARTITIONS = ('rtl/UAlink2.0', 'verification/UAlink2.0', 'simulator/UAlink2.0')
PROJECT = 'verification/UAlink2.0/project'
MANIFEST = 'verification/UAlink2.0/.ualink-export.json'
LINKS = {PROJECT+'/rtl':'../../../rtl/UAlink2.0', PROJECT+'/verification':'..',
         PROJECT+'/model':'../../../simulator/UAlink2.0/model',
         PROJECT+'/simulator':'../../../simulator/UAlink2.0'}
MARKERS = {'verification/UAlink2.0/.ualink-root':b'project\n',
           'simulator/UAlink2.0/.ualink-root':b'../../verification/UAlink2.0/project\n'}
IGNORE = b'''# Generated export namespace: runtime artifacts are not source.
__pycache__/
.pytest_cache/
*.pyc
*.pyo
*.vvp
*.vcd
*.fst
*.wdb
*.wlf
*.ghw
*.log
*.jou
*.o
*.a
build/
reports/
artifacts/
'''
PROJECT_DIRS = {'scripts','config','docs','specs','variants','third_party'}
PROJECT_FILES = {'README.md','Makefile','AGENTS.md','.gitignore','LICENSE','LICENSE.md','COPYING'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def git(source, *args):
    r=subprocess.run(['git','-C',str(source),*args],capture_output=True)
    require(r.returncode==0, 'git failed: '+r.stderr.decode('utf-8',errors='replace').strip())
    return r.stdout


def safe_relative(name):
    require(isinstance(name,str) and name and '\\' not in name and
            all(ord(c)>=32 for c in name), 'unsafe path')
    p=PurePosixPath(name)
    require(not p.is_absolute() and all(c not in ('..','.') for c in p.parts) and
            p.as_posix()==name, 'unsafe path: '+name)
    return p


def owned_path(name):
    safe_relative(name)
    require(any(name.startswith(prefix+'/') for prefix in PARTITIONS), 'path outside owned partitions: '+name)
    require(name!=MANIFEST, 'manifest cannot own itself')


def exclusion(name):
    p=safe_relative(name)
    if p.parts[0] in {'build','reports','artifacts','.git','.erie-verilog-generator-state'}:
        return 'generated_or_repository_internal'
    if 'private' in p.parts or '__pycache__' in p.parts or name=='config/local.json' or p.name=='.env' or p.name.startswith('.env.'):
        return 'private_or_local_input'
    if p.suffix in {'.pyc','.vcd','.fst','.wdb','.vvp','.o','.a','.dcp','.bit','.wlf','.ghw'}:
        return 'generated_binary'
    if p.parts[0]=='third_party' and p.suffix not in {'.md','.json','.yaml','.yml','.toml','.txt','.sha256'}:
        return 'external_dependency_payload'
    return None


def mapped(name):
    p=safe_relative(name)
    first=p.parts[0]
    if first=='rtl':return 'rtl/UAlink2.0/'+p.relative_to('rtl').as_posix()
    if first=='verification':return 'verification/UAlink2.0/'+p.relative_to('verification').as_posix()
    if first=='model':return 'simulator/UAlink2.0/'+name
    if first=='simulator':return 'simulator/UAlink2.0/'+p.relative_to('simulator').as_posix()
    require(first in PROJECT_DIRS or name in PROJECT_FILES, 'unmapped tracked source: '+name)
    return PROJECT+'/'+name


def constructor_names(tree):
    names=set();modules=set()
    for node in ast.walk(tree):
        if isinstance(node,ast.ImportFrom) and node.module=='pathlib':
            names.update(a.asname or a.name for a in node.names if a.name=='Path')
        if isinstance(node,ast.Import):
            modules.update(a.asname or a.name for a in node.names if a.name=='pathlib')
    return names,modules


def path_distance(node, names, modules):
    """Count only known __file__ Path ancestry, never arbitrary .parents text."""
    if isinstance(node,ast.Call):
        f=node.func
        is_path=(isinstance(f,ast.Name) and f.id in names) or (
            isinstance(f,ast.Attribute) and f.attr=='Path' and isinstance(f.value,ast.Name) and f.value.id in modules)
        if is_path and len(node.args)==1 and not node.keywords and isinstance(node.args[0],ast.Name) and node.args[0].id=='__file__':return 0
        if isinstance(f,ast.Attribute) and f.attr=='resolve' and not node.args and not node.keywords:
            return path_distance(f.value,names,modules)
    if isinstance(node,ast.Attribute) and node.attr=='parent':
        n=path_distance(node.value,names,modules)
        return None if n is None else n+1
    if isinstance(node,ast.Subscript) and isinstance(node.value,ast.Attribute) and node.value.attr=='parents':
        index=node.slice
        if isinstance(index,ast.Constant) and type(index.value) is int and index.value>=0:
            n=path_distance(node.value.value,names,modules)
            return None if n is None else n+index.value+1
    return None


def transform_python(name, raw):
    # CPython AST column offsets are UTF-8 bytes; preserve comments and strings verbatim.
    bom=raw.startswith(b'\xef\xbb\xbf');text=raw.decode('utf-8-sig');encoded=text.encode('utf-8')
    tree=ast.parse(text,filename=name);names,modules=constructor_names(tree)
    depth=len(PurePosixPath(name).parts)
    offsets=[0]
    for line in encoded.splitlines(keepends=True):offsets.append(offsets[-1]+len(line))
    def span(node):return offsets[node.lineno-1]+node.col_offset,offsets[node.end_lineno-1]+node.end_col_offset
    root_names=set()
    for node in tree.body:
        if isinstance(node,ast.Assign) and path_distance(node.value,names,modules)==depth:
            root_names.update(t.id for t in node.targets if isinstance(t,ast.Name))
        if isinstance(node,ast.AnnAssign) and isinstance(node.target,ast.Name) and node.value is not None and path_distance(node.value,names,modules)==depth:
            root_names.add(node.target.id)
    changes=[]
    for node in ast.walk(tree):
        distance=path_distance(node,names,modules)
        start,end=span(node) if hasattr(node,'end_lineno') and node.end_lineno else (0,0)
        if distance==depth:
            original=encoded[start:end].decode('utf-8')
            replacement=("(lambda _ualink_file: next(((_ualink_dir / "
                         "(_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() "
                         "for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), "
                         +original+"))(__import__('pathlib').Path(__file__).resolve())")
            changes.append((start,end,replacement,dict(kind='project_root',line=node.lineno,original=original)))
        # Specific self-file identity operation: ROOT must be a known source-root binding.
        if isinstance(node,ast.Call) and isinstance(node.func,ast.Attribute) and node.func.attr=='relative_to' and \
           len(node.args)==1 and not node.keywords and isinstance(node.args[0],ast.Name) and node.args[0].id in root_names and \
           path_distance(node.func.value,names,modules)==0:
            original=encoded[start:end].decode('utf-8')
            replacement="__import__('pathlib').Path("+repr(name)+")"
            changes.append((start,end,replacement,dict(kind='source_identity',line=node.lineno,original=original,source_path=name)))
    # resolve() can wrap the same root expression; replace only the outermost match.
    selected=[]
    for change in sorted(changes,key=lambda c:(c[0],-c[1])):
        if any(a<=change[0] and change[1]<=b for a,b,*_ in selected):continue
        require(not any(change[0]<b and a<change[1] for a,b,*_ in selected), 'overlapping root transformation: '+name)
        selected.append(change)
    result=encoded
    for start,end,replacement,_ in reversed(selected):result=result[:start]+replacement.encode('utf-8')+result[end:]
    ast.parse(result.decode('utf-8'),filename=name)
    return (b'\xef\xbb\xbf' if bom else b'')+result,[c[3] for c in selected]


def transform_readme(name, raw):
    if name not in ('verification/README.md','rtl/README.md'):return raw,[]
    text=raw.decode('utf-8')
    prefix='project/docs/' if name.startswith('verification/') else '../../verification/UAlink2.0/project/docs/'
    count=text.count('(../docs/')
    text=text.replace('(../docs/','('+prefix)
    if name=='verification/README.md':
        text+='\n## Overflow 分区运行入口\n\n从 Overflow 仓库根执行：\n\n```sh\ncd verification/UAlink2.0/project\nmake test\n```\n\n工程根通过受管相对链接访问 RTL、验证与模拟器；外部授权依赖仍须显式提供。\n'
    changes=[dict(kind='entry_readme',relative_doc_links=count,project_run_hint=name=='verification/README.md')]
    return text.encode('utf-8'),changes


def source_tree(source, commit):
    require(re.fullmatch(r'[0-9a-fA-F]{7,64}',commit) is not None, 'commit must be an immutable hexadecimal Git object ID, not a branch')
    resolved=git(source,'rev-parse','--verify',commit+'^{commit}').decode().strip()
    rows=[];excluded=[]
    for entry in git(source,'ls-tree','-rz','--full-tree',resolved).split(b'\0'):
        if not entry:continue
        info,path=entry.split(b'\t',1);mode,kind,oid=info.decode().split();name=path.decode('utf-8')
        reason=exclusion(name)
        if reason:excluded.append(dict(source=name,reason=reason));continue
        require(kind=='blob' and mode in ('100644','100755'), 'source symlinks/gitlinks are not exported: '+name)
        rows.append((name,mode,oid))
    proc=subprocess.run(['git','-C',str(source),'cat-file','--batch'],input=(''.join(oid+'\n' for _,_,oid in rows)).encode(),capture_output=True)
    require(proc.returncode==0,'git blob read failed')
    cursor=0;files={};payloads={}
    def add(target,metadata,payload=None):
        owned_path(target)
        require(target not in files,'mapping collision: '+target)
        require(not any(target.startswith(p+'/') or p.startswith(target+'/') for p in files),'file/directory mapping collision: '+target)
        files[target]=metadata
        if payload is not None:payloads[target]=payload
    for name,mode,oid in rows:
        end=proc.stdout.index(b'\n',cursor);header=proc.stdout[cursor:end].decode().split();cursor=end+1
        require(len(header)==3 and header[0]==oid and header[1]=='blob','invalid git batch response')
        size=int(header[2]);raw=proc.stdout[cursor:cursor+size];cursor+=size+1
        require(len(raw)==size and proc.stdout[cursor-1:cursor]==b'\n','truncated git blob')
        data,changes=transform_python(name,raw) if name.endswith('.py') else transform_readme(name,raw)
        target=mapped(name)
        add(target,dict(kind='file',mode=0o755 if mode=='100755' else 0o644,sha256=sha(data),
                        source=name,source_sha256=sha(raw),source_git_blob=oid,transformations=changes),data)
    for prefix in PARTITIONS:add(prefix+'/.gitignore',dict(kind='file',mode=0o644,sha256=sha(IGNORE),generated='namespace_ignore'),IGNORE)
    for path,data in MARKERS.items():add(path,dict(kind='file',mode=0o644,sha256=sha(data),generated='root_marker'),data)
    for path,target in LINKS.items():add(path,dict(kind='symlink',target=target,generated='compatibility_link'))
    manifest=dict(owner=OWNER,schema=SCHEMA,source_commit=resolved,files=files,excluded=excluded,
                  exporter_sha256=sha(Path(__file__).read_bytes()))
    return manifest,payloads


def safe_destination(dest, name):
    safe_relative(name)
    current=dest
    require(dest.is_dir() and not dest.is_symlink(),'destination must be an existing real directory')
    for part in PurePosixPath(name).parts[:-1]:
        current=current/part
        require(not current.is_symlink(),'destination parent symlink: '+str(current))
        require(not current.exists() or current.is_dir(),'destination parent is not a directory: '+str(current))
    return dest/name


def snapshot(path):
    if path.is_symlink():return ('symlink',os.readlink(path))
    if not path.exists():return None
    require(path.is_file() and stat.S_ISREG(path.stat().st_mode),'destination is not a regular file: '+str(path))
    return ('file',path.read_bytes(),stat.S_IMODE(path.stat().st_mode))


def validate_old(manifest):
    require(isinstance(manifest,dict) and manifest.get('owner')==OWNER and manifest.get('schema')==SCHEMA,'unrecognized ownership manifest')
    require(isinstance(manifest.get('files'),dict),'invalid ownership entries')
    for path,item in manifest['files'].items():
        owned_path(path);require(isinstance(item,dict),'invalid ownership entry')
        if item.get('kind')=='file':
            require(re.fullmatch('[0-9a-f]{64}',item.get('sha256','')) is not None and item.get('mode') in (0o644,0o755),'invalid owned file identity')
        else:require(item.get('kind')=='symlink' and path in LINKS and item.get('target')==LINKS[path],'invalid owned symlink boundary')


def matches(observed, item):
    if observed is None:return False
    if item['kind']=='symlink':return observed==('symlink',item['target'])
    return observed[0]=='file' and sha(observed[1])==item['sha256'] and observed[2]==item['mode']


def replace(path, value):
    """Replace one already-preflighted file/link atomically, without following its leaf."""
    handle,temp=tempfile.mkstemp(prefix='.ualink-export-',dir=path.parent);os.close(handle)
    temporary=Path(temp)
    try:
        if value[0]=='symlink':temporary.unlink();temporary.symlink_to(value[1])
        else:temporary.write_bytes(value[1]);temporary.chmod(value[2])
        os.replace(temporary,path)
    finally:
        if temporary.exists() or temporary.is_symlink():temporary.unlink()


def export(source, commit, dest, check=False):
    manifest,payloads=source_tree(source,commit)
    manifest_path=safe_destination(dest,MANIFEST);before_manifest=snapshot(manifest_path)
    require(before_manifest is None or before_manifest[0]=='file','manifest may not be a symlink')
    old=json.loads(before_manifest[1]) if before_manifest else None
    if old is not None:validate_old(old)
    else:
        for prefix in PARTITIONS:
            path=safe_destination(dest,prefix+'/placeholder').parent
            require(not path.exists() or (path.is_dir() and not any(path.iterdir())), 'unowned nonempty partition: '+str(path))
    oldfiles={} if old is None else old['files'];files=manifest['files'];observed={}
    # Verify ALL old ownership and new collisions before creating a directory or file.
    for name in sorted(set(oldfiles)|set(files)):
        path=safe_destination(dest,name);value=snapshot(path);observed[name]=value
        if name in oldfiles and value is not None:
            require(matches(value,oldfiles[name]),'modified owned path, refusing overwrite/removal: '+name)
        if name in files and name not in oldfiles:
            require(value is None,'unowned target collision: '+name)
    updates=[name for name in sorted(files) if not matches(observed[name],files[name])]
    removals=[name for name in sorted(oldfiles) if name not in files and observed[name] is not None]
    manifest_bytes=(json.dumps(manifest,indent=2,sort_keys=True,ensure_ascii=False)+'\n').encode('utf-8')
    desired_manifest=('file',manifest_bytes,0o644)
    manifest_changed=before_manifest!=desired_manifest
    summary=dict(source_commit=manifest['source_commit'],source_files=sum('source' in f for f in files.values()),
                 excluded=len(manifest['excluded']),root_transformations=sum(len(f.get('transformations',[])) for f in files.values()),
                 managed_paths=len(files),updates=updates,removals=removals,manifest_changed=manifest_changed,
                 readonly=check,up_to_date=not updates and not removals and not manifest_changed,manifest=MANIFEST)
    if check:return summary
    changed=[];created_dirs=[]
    def parents(path):
        pending=[];current=path.parent
        while current!=dest and not current.exists():pending.append(current);current=current.parent
        for p in reversed(pending):p.mkdir();created_dirs.append(p)
    try:
        for name in updates+removals:
            path=safe_destination(dest,name)
            require(snapshot(path)==observed[name],'destination changed during export: '+name)
            if name in files:
                parents(path);item=files[name]
                value=('symlink',item['target']) if item['kind']=='symlink' else ('file',payloads[name],item['mode'])
                replace(path,value)
            else:path.unlink()
            changed.append((name,observed[name]))
        if manifest_changed:
            require(snapshot(manifest_path)==before_manifest,'manifest changed during export')
            parents(manifest_path);replace(manifest_path,desired_manifest)
            changed.append((MANIFEST,before_manifest))
    except Exception:
        for name,previous in reversed(changed):
            path=safe_destination(dest,name)
            if previous is None:
                if path.exists() or path.is_symlink():path.unlink()
            else:replace(path,previous)
        for path in reversed(created_dirs):
            try:path.rmdir()
            except OSError:pass
        raise
    return summary


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,default=ROOT)
    parser.add_argument('--commit',required=True)
    parser.add_argument('--dest',type=Path,required=True)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    try:
        # Do not resolve away a destination symlink before validating its boundary.
        result=export(args.source.absolute(),args.commit,args.dest.absolute(),args.check)
        print(json.dumps(result,indent=2,sort_keys=True))
        return 0
    except (ValueError,OSError,KeyError,TypeError,SyntaxError,UnicodeError) as error:
        print('EXPORT FAIL: '+str(error),file=sys.stderr)
        return 1


if __name__=='__main__':raise SystemExit(main())
