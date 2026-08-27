import importlib.util
from pathlib import Path


ROOT = Path(__file__).parents[4]
CHECKER = ROOT / "scripts" / "check_repository.py"


def load_checker():
    spec = importlib.util.spec_from_file_location("check_repository", CHECKER)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_repository_gate_excludes_generated_work_and_cache_files(
    tmp_path, monkeypatch
) -> None:
    checker = load_checker()
    source = tmp_path / "rtl" / "kdlink" / "source.v"
    generated = tmp_path / "verification" / "kdlink" / "coverage" / "work"
    cache = tmp_path / "simulator" / "kdlink" / "__pycache__"
    source.parent.mkdir(parents=True)
    generated.mkdir(parents=True)
    cache.mkdir(parents=True)
    source.write_text("module source; endmodule\n", encoding="utf-8")
    host_path = "/" + "home/example"
    (generated / "host.mk").write_text(f"ROOT={host_path}\n", encoding="utf-8")
    (cache / "module.pyc").write_bytes(b"generated")
    monkeypatch.setattr(checker, "ROOT", tmp_path)
    assert checker.project_files() == [source]
