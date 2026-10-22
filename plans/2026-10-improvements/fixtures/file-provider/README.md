# Q01 固定文件样本

在仓库根目录运行，输出目录必须尚不存在：

```sh
python3 plans/2026-10-improvements/fixtures/file-provider/generate.py --output /tmp/interline-q01
```

需要超限样本时增加 `--include-oversized`，生成 20 MiB + 1 字节文件；默认只生成小文件。
生成物放入测试设备的本地文件提供器，再复制到 iCloud，按 `09-file-provider-acceptance.md`
逐项执行。源文本为原创验收内容，不使用私人资料。脚本拒绝覆盖已有目录。

UTF-8、带 BOM 的 UTF-16 LE/BE、GB18030 具有相同两章正文。先导入其中一个，再选择其他
编码或 duplicate 文件，预期同一稳定书 ID，不重复建书。空文件须拒绝；NUL 文件在明确
选择 UTF-8 时须拒绝，不能把其他编码的解码结果当作同一测试。

`expected.json` 记录源字节数、SHA-256、编码、预期章节与书 ID。它是验收预期，不能代替
应用实际解析、系统文件选择、重启、源文件保全及失败重试的证据。
v1/v2 备份仍由实际受测应用导出并记录其 SHA 和字节数；本脚本不伪造“已验证备份”。
