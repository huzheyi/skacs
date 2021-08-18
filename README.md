# Shadowsocks-libev+kcptun+AdGuardHome+ChinaDNS-NG+SmartDNS for EdgeRouter-X(-SFP) a.k.a Skacs

Skacs方案，整合了Shadowsocks-libev+kcptun+AdGuardHome+ChinaDNS-NG+SmartDNS，特别为EdgeRouter-X(-SFP)用户提供二进制文件，以满足纯净DNS、透明代理和广告过滤等科学上网需求。

## 组件(及其依赖)的版本信息

| 名称 | 版本 | 是否源码编译 | 编译(发布)日期 |
| --- | --- | --- | --- |
| [Shadowsocks-libev](https://github.com/shadowsocks/shadowsocks-libev) | 3.3.4 | Y | 2020-04-25 |
| *[libsodium](https://www.libsodium.org/)* | 1.0.18 | Y | 2020-04-21 |
| *[mbedtls](https://tls.mbed.org/)* | 2.16.6 | Y | 2020-04-21 |
| *[c-ares](https://c-ares.haxx.se/)* | 1.16 | Y | 2020-04-23 |
| *[libev](http://libev.schmorp.de/)* | 4.33 | Y | 2020-04-23 |
| [kcptun](https://github.com/xtaci/kcptun) | 20200409 | N | 2020-04-09 |
| [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome) | 0.101.0 | N | 2020-03-13 |
| [ChinaDNS-NG](https://github.com/zfl9/chinadns-ng) | 1.0-beta.22 | Y | 2020-04-23 |
| [SmartDNS](https://github.com/pymumu/smartdns) | 1.2020.04.23-1627 | Y | 2020-04-23 |
| *[openssl](https://www.openssl.org/)* | 1.1.0l | N | 2020-04-23 |

> 注：
> * Shadowsocks-libev采用部分动态链接编译，strip后体积相当小
> * 源码编译平台为Debian Stretch (Based on qemu-system-mipsel)

## 功能说明

* DNS解析过程:

        客户端请求 --> dnsmasq -(转发)-> AdGuard Home -(过滤后转发)-> ChinaDNS-NG
        -(可信域名)-> ISPDNS
        -(黑名单域名)-> SmartDNS

* 系统通过dnsmasq将所有客户端的DNS请求转发至AdGuard Home，AdGuard Home在进行广告过滤后，将请求转发至上游ChinaDNS-NG，ChinaDNS-NG将根据规则转发至上游国内DNS和可信DNS，SmartDNS支持采用多种DNS查询协议并选出最佳IP地址                
* 根据DNS解析结果，境内外流量通过iptables规则分流，境外流量转发至shadowsocks服务
* 默认劫持所有对udp/53的请求，按照上述规则进行DNS解析

## 使用说明

1. 将本项目克隆后，将`skacs`目录放至设备`/config/`目录下，`init.sh`脚本放至设备`/config/scripts/post-config.d/`目录下，`/config/`目录不会因系统固件更新而丢失
2. `skacs/iplist.sh`更新gfwlist黑名单和境内IP列表
3. 按照实际情况，配置`skacs/conf/`目录下的Shadowsocks-libev、kcptun等配置文件
4. `sudo skacs/bin/skacs.sh start｜stop|restart|status`，分别为启动、停止、重启和查看服务
5. 首次启动后浏览器访问路由器3000端口，对AdGuard Home做初始配置

## 参数配置

1. 启动脚本`skacs/bin/skacs.sh`中的ISPDNS和BYPASS_RANGE，可根据实际情况配置
2. ss-redir默认监听在1081端口，同时ss-local提供socks5代理，默认监听在1080端口
3. AdGuard Home首次运行需访问3000端口页面做初始化配置，默认配置监听在5300端口，并配置上游DNS为ChinaDNS-NG
4. ChinaDNS-NG默认监听在5301端口，默认采用gfwlist黑名单模式，国内上游DNS为ISPDNS(默认配置119.29.29.29)，可信上游DNS为SmartDNS
5. SmartDNS默认监听在5302端口，默认配置上游DoT，DoH
6. 由于kcptun占用内存较多默认未启用，如有需求可根据实际情况去掉启动脚本中的相关注释

> 注：
> * 由于不具备公网IPv6，故本工具暂时只支持处理IPv4访问，如有需求可自行调整配置或整合[ss-tproxy](https://github.com/zfl9/ss-tproxy/blob/master/ss-tproxy)工具使用

## 鸣谢

感谢以上所有开源软件的作者！





