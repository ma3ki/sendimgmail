# sendimgmail
This script attaches a graph image to the alert email that Zabbix transmits.
## Installation
install script

```
$ cd /etc/zabbix/alert
$ curl -O https://raw.githubusercontent.com/ma3ki/sendimgmail/master/sendimgmail.sh
$ curl -O https://raw.githubusercontent.com/ma3ki/sendimgmail/master/sendimgmail.conf
$ chmod 755 sendimgmail.sh
```

install mutt command

```
$ sudo yum install mutt
```

## Script setting

```
$ vi sendimgmail.conf
```

Setting field and value

|field|value|description|default|
|---|---|---|---|
|ZABBIX_URL|String|Zabbix web URL|http://127.0.0.1/zabbix|
|ZABBIX_USER|String|Login user|admin|
|ZABBIX_PASS|String|Login password|zabbix|
|BASIC_USER|String|Basic authentication user|-|
|BASIC_PASS|String|Basic authentication password|-|
|MODE|0 or 1|Attachment mode (0=graph,1=screen)|0|
|IMAGE_TEMP|String|Working deirectory|/var/tmp/imgtmp|
|MAIL_FROM|String|From email address|hogehoge@example.com|
|MAIL_NAME|String|Display name of the email|zabbix_alert|
|SMTP_URL|String|SMTP server URL for mutt command|smtp://127.0.0.1:25|
|PRITEXT|String|Syslog facility and level|user.info|
|VERBOSE|0 or 1|Logging mode (0=info,1=debug)|1|
|PROCESS_LIMIT|integer|Maximum processes|10|
|CURLOPTS|String|curl options| --silent --show-error|

## Zabbix Web setting

### Media Types
Create media type

```
Name: sendimgmail
Type: Script
Script: name sendimgmail.sh
```

### Users
Add Users Media

```
Type: sendimgmail
Send to: your email address
```

### Actions
Set the following messages in an action message. (Default message and Recovery message)

```
host: {HOSTNAME}
key: {TRIGGER.KEY}
```

set Operations

```
Sent to Users: your username
Send only to: sendimgmail
```

## How to get graphs
1. Log in to Zabbix Web.
2. Get "hostid" from "{HOSTNAME}".
3. Get "itemid" from "{TRRIGER.KEY}".
4. Get "graphid" from "hostid" and "itemid".
5. Get graph images.
6. Send email.

