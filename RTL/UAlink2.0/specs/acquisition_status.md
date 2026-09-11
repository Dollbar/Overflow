# 规范接入状态

更新：2026-09-07。此文件不包含申请人的姓名、邮箱、Cookie 或提交凭据。

## 当前状态：用户已手动提供 PDF

三份正文已接入 `private/`，完成标题/修订版、页数、文件大小及 SHA-256 登记，均可正常解析、无 PDF 加密。校验值用于固定本地阅读输入，不等于已与联盟签名或官方校验值验证真实性。

| 本地文件对应规范 | 修订版 | 页数 | 大小（bytes） |
| --- | --- | --- | --- |
| Common | 2.0 | 249 | 10,699,046 |
| Data Link and Physical Layers 200G | 2.0 | 106 | 3,179,634 |
| Manageability | 1.0 | 71 | 4,970,944 |

合计 426 页、18,849,624 bytes。文件清单与哈希存于 `private/inventory.json`；正文与抽取文本不提交。首轮研读见 正文研读报告（历史文档已清理）。尚未完成全部条款审查、勘误核定与许可范围审查。

## 历史记录：自动表单申请

用户明确授权接受评估协议、下载规范，并提供必填身份信息后，已通过独立浏览器会话在官方页面填写字段、勾选同意并点击提交。没有跳过表单或人为绕过 reCAPTCHA，也没有提交会员申请或购买 IP。

| 申请文档 | 当时提交结果 | 当时自动下载状态 |
| --- | --- | --- |
| [Common 2.0](https://ualinkconsortium.org/specification/ualink-common-2-0-specification/) | 页面返回联系确认 | 未提供下载链接，未下载 |
| [200G DL/PL 2.0](https://ualinkconsortium.org/specification/ualink-data-link-and-physical-layers-2-0-specification/) | 页面返回联系确认 | 未提供下载链接，未下载 |
| [Manageability 1.0](https://ualinkconsortium.org/specification/ualink-manageability-1-0-specification/) | 页面返回联系确认 | 未提供下载链接，未下载 |

三份页面均显示已收到联系请求、稍后联系的通用确认。检查提交后页面链接，没有规范正文链接；浏览器下载事件数为 0。这只能证明页面返回了提交确认，不能证明后台审批完成、邮件已发出或许可已经生效。

上述自动下载缺口已由用户手动提供 PDF 解决，不再要求重复提交表单。本工程未访问申请人的邮箱。

私有提交回执位于 `private/download_receipt.json`，申请字段在 `private/download_request.json`；这些文件以及浏览器会话均被 Git 忽略。下载辅助工具已执行一次，不应重复运行以免重复提交。

评估用途与后续实施/发布权利继续分别管理。机器状态保留自动下载数量 0，另记用户提供数量 3，不将手动接入冒记成自动下载成功。
