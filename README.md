# 自动签到说明

这个仓库通过 GitHub Actions 每天定时执行签到脚本，支持两个 New API 站点。

## 签到站点

| 站点 | 地址 | 脚本 | Secrets |
|------|------|------|---------|
| 站点1 | ai.xem8k5.top | checkin.sh | CHECKIN_USERNAME / CHECKIN_PASSWORD |
| 站点2 | api.denxio.top | checkin2.sh | CHECKIN_USERNAME2 / CHECKIN_PASSWORD2 |

## 触发时间

```yaml
- cron: '0 0 * * *'
```

- UTC 时间：每天 `00:00`
- 北京时间：每天 `08:00`

## GitHub Secrets 配置

在仓库 `Settings -> Secrets and variables -> Actions` 中设置：

- `CHECKIN_USERNAME` — 站点1 登录邮箱
- `CHECKIN_PASSWORD` — 站点1 密码
- `CHECKIN_USERNAME2` — 站点2 登录邮箱
- `CHECKIN_PASSWORD2` — 站点2 密码

## 脚本工作流程

每个签到脚本执行以下步骤：

1. 检查环境变量是否完整
2. 登录获取 Cookie 和用户信息
3. 查询签到前状态（今日是否已签到）
4. 若未签到则调用签到接口
5. 查询签到后状态，确认今日签到记录存在
6. 若签到后仍未确认，脚本返回失败（避免 GitHub Actions 假成功）

## 调试

手动触发 workflow 后查看日志，搜索关键字：
- `登录成功` / `登录失败`
- `签到响应`
- `签到后状态`
- `签到成功` / `今日已签到` / `签到失败`

## 可选优化

如果想要更早签到，修改 cron 时间：
```yaml
# 北京时间 7:00
- cron: '0 23 * * *'
```
