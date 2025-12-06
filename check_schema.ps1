# 临时脚本：查看Name2Id表结构
$dbPath = "C:\Users\Lenovo\Documents\xwechat_files\wxid_t0lk4ald194u22_937e\db_storage\message\message_0.db"
$key = "1126d5bc8e0549a4b38fc16ae342ba1a"
$tempDb = "C:\Users\Lenovo\Desktop\WXAgent\temp_check.db"

# 解密
Write-Host "Decrypting..."
cd C:\Users\Lenovo\Desktop\WXAgent\backend
.\wxagent_backend.exe decrypt-db --input $dbPath --key $key --output $tempDb

# 查看表结构
Write-Host "`nName2Id table schema:"
sqlite3 $tempDb "PRAGMA table_info(Name2Id)"

Write-Host "`n`nSample data:"
sqlite3 $tempDb "SELECT * FROM Name2Id LIMIT 3"

# 清理
Remove-Item $tempDb -ErrorAction SilentlyContinue
