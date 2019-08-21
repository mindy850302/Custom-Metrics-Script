# 打沙包懶人包

# Default套路 - 標準三層式結構
### EC2 Level
1. Create空的ElB
2. CloudFront指定origin到ELB
    > 都先default cache
3. 驗證Instance服務如何運作
4. Create AMI打包instance application
5. 修改user data
    > if needed
6. 灌進Launch Template/Configuration裡面）
    > prefer template if available
7. 起ASG並灌user data
8. 掛進ELB
9. 設定Cloudwatch跟ScalingPolicy
    > 
10. 塞ELB Endpoint接應流量
11. 測試CloudFront是否能正常access服務
    > 在這階段驗證Header, TTL, Cookie, QueryString的配置
12. 換成CloudFront接應流量
13. 監控整體運作狀況，做適當調整

# Compute

## ＊EC2
- 先驗證userdata是否有陷阱
    > 腳本不完全、開頭沒有`#!/bin/bash`、套件少安裝、權限不足等等問題 
- 先搞懂EC2當中application怎麼動作的，以便後續ELB驗證
    - HTTP
    - Health check的path、機制、duration
    - Binary
    - Script
    - ...之類的
- 要固定Public IP的話需要透過Elastic IP解決
- 同時最多可以開幾台機器在 ***EC2 Limits*** 裡面找
    > 不夠的話，看能不能發Support調整數量

### AutoRecovery
1. 針對Physical的health check做listening，有問題則保留EC2 metadata轉移到另一台Physical Host
2. EC2 > Status Check > Alarm > Repair this instance

### [VMImport](https://docs.aws.amazon.com/vm-import/latest/userguide/vmimport-image-import.html)
> 應該不會出，以防萬一可以去找官方文件有懶人包
1. 在地端VM上做一狗票事前確認：關防火牆、enable DHCP...等等，讓他可以適用於VPC配發網路訊息
2. 匯出成vhd/vmdk
3. 上傳vhd/vmdk到S3
    > 比賽有出題的話，應該會準備好到這
4. 建立VMImport要用到的IAM Role
5. `aws ec2 import-image --description "blablabla" --license-type <value> --disk-containers "file://C:\import\containers.json"`
    > license-type會定義給你看要byol還是aws發

    Json裡面定義一些關於哪個disk要轉ami的訊息
    ```
    [{
        "Description": "Ubuntu 2019.04",
        "Format": "vmdk",
        "UserBucket": {
            "S3Bucket": "import-images",
            "S3Key": "vmdk/ubuntu2019-04.vmdk"
        }
    }]
    ```
    然後會吐一個task id回來
6. `aws ec2 describe-import-image-tasks --import-task-ids import-ami-abcd1234`
    換掉task id去看現在進程到哪邊
7. 轉完後，會在AMI console上面看到那個ami，再看看出來看能不能順利開成ec2

### AMI
- 記得要打包，不要勾`No reboot`，做完整的package比較保險

### AutoScaling
- Prefer用Launch Template，設定上相對快速、彈性
    > 可以在架構上highlight這點（？
- 如果允許混搭，那就可以混instance types & pricing options
- Health check通常會搭配用ELB，選成EC2的話會以檢查physical host function為主

### Instance Type
- 看有沒有用對，但八成會限定`t2.micro`
- 不然可以搭配AutoScaling做混搭的request

### Spot Instance / Fleet
> 八成沒權限

### Instance Store
- 要注意一但Stop/Terminated就會消失
- 最好轉存到EBS、CloudWatch Logs上面做長期Store

### EBS
- Snapshot
- Encryption
    - used volume wanna be encryted
    - 建Volume/Launch Instance的時候就要選
    - 後續若要做變更僅有兩種方法：
        1. copy to new
        2. create new -> 倒資料進去
- Cross region replica
    - 複製Snapshot/AMI過去backup region

### EFS
- Cross region
    - 可以透過VPC Peering的方式，把網路環境串接起來，在一台機器上面mount不同account/region的efs，在機器當中做replica
- [backup plan](https://docs.aws.amazon.com/efs/latest/ug/efs-backup-solutions.html)
    1. AWS Backup Service
    2. EFS對抄

## ＊ECS
- 建Service的時候如果沒有特別指定說要Service Discovery，就把勾勾勾掉
### ECR
- 建好會有`docker push <ECR_TAG>`的資訊可以複製貼上
- 請記得點開`View push commands`

### Docker command
- `docker login`登入ECR
- `docker build -t <TAG> <PATH_OF_DOCKERFILE>` 抓dockerfile打包image
- `docker run -d -p <HOST_PORT>:<CONTAINER_PORT> <IMAGE_TAG>` 跑起來看
- `docker ps -a` 看所有運行中的container
- `docker images -a` 列出host上面的images 

### ＊ECS Service
https://gitlab.com/ecloudture/aws/aws-ecs-workshop

- 會先跟你說service port在哪邊，或是用`docker run`那個images下去之後用`docker ps`看expose port是哪個
- 把UserData打包進dockerfile當中，記得前面要加`RUN`
- 如果有需要類似開機腳本，用`CMD`指定Container跑起來後要執行什麼動作
- 一樣先在localhost先run起來，確認服務怎麼走得再繼續
- ***Port mapping一定要注意***，最好是用`bridge`
- `awsvpc`目前僅適用AWS Fargate，當Container/Task起來後會mapping一個vpc ip上去
- 直接選`BalancedAZ Binpack`
- AutoScaling規則，看loading在哪邊再去tuning就行
- register to target group，只有創建service當下可以mapping到target group，若有變更就要recreate service

## Lambda
- https://github.com/ecloudvalley/Run-Serverless-CICD-Pipeline-with-AWS-CodeStar-and-Develop-with-AWS-Cloud9
- https://gitlab.com/ecloudture/olympic/build-serverless-environment-with-aws-lambda
- https://gitlab.com/ecloudture/aws/aws-ai-workshop
- event-driven automation workload
- deploy with API Gateway
- 需要放進去VPC的話，那個subnet ***需要有NAT routing才會讓lambda有訪問internet的能力***
    > Lambda沒有配發public ip的關係
- IAM role需要注意至少要有`basicexecution`或cloudwatch權限，才能透過cloudwatch log檢視狀況
    > 方便debug
- timeout & memory注意要調整

# S3
https://gitlab.com/ecloudture/olympic/private/s3-storage-class-lifecycle-policy
https://gitlab.com/ecloudture/olympic/aws-s3-cors
### Cross region replica
1. 要先建好replica對象Bucket
2. 設定完成之後的動作，才會複寫過去
### Access log
- 要開就開ㄅ：https://docs.aws.amazon.com/AmazonS3/latest/user-guide/server-access-logging.html
### Bucket policy
- 看[Sample](https://docs.aws.amazon.com/AmazonS3/latest/dev/example-bucket-policies.html)去改規則，改成題目所要求的

### Block public access
- 有那個 ***Block public access*** 要關掉
- account/bucket兩個層級都要確認

### [Request rate limit](https://aws.amazon.com/about-aws/whats-new/2018/07/amazon-s3-announces-increased-request-rate-performance/)
- 加減注意會不會撞到這個
- 應該是很難



# Network
- Multi office could communicate with each other
> SA Pro/Networking的範圍

## ＊VPC
- Public流量檢查，記得Instance要有Public IP
![](https://i.imgur.com/gtD3WLb.png)
- Private的就多一層NAT
![](https://i.imgur.com/nLDslw0.jpg)
- 記得NAT要放在Public Subnet中才能運作
- 一堆舞ㄟ謀ㄟ的眉角要去看[Netwokring筆記
](https://paper.dropbox.com/doc/Networking-YofiQ5plUchSSQe1G0gky#:uid=559309021804696798151534&h2=Tips)
### DNS Resolver
- VPC內要開兩個設定才會讓DNS正常服務：
    1. enableDNSHostname
    2. enableDNSSupport
### Route Table
- 路由紀錄有可能隨時會被改
### NAT Instance / Gateway
- 比較哪一個比較貼近實務場景，一般是建議透過NAT GW實作
- 為了可用性＆效能考量，會建議一個AZ配置一個NAT GW，但這樣Route Table就會比較複雜些 → ***從中要做取捨***
### Security Group
- Security Group只有對外Public的部分才allow `0.0.0.0/0`，不然一率用SG Chain做串接
- ***有可能隨時會被改***
### NACL
- outbound只讓最小流量出去，像是SSH, HTTP, HTTPS
- inbound ***有明確不允許*** 哪些流量、針對大量IP要做Deny的時候再設定
- ***有可能隨時會被改***
### Network bottleneck
- Instance Type頂到肺
- NAT GW port炸裂

## ELB
- Target group的health check機制注意
- keepalive如果有特別說的話再改
### Session
- 看sticky seesion的需求
### Routing Algorithm
- ALB上面可以在每一個listener去針對不同需求下規則，Path/Host/Port導流到不同的target group當中處理
### SSL Termination
- 把HTTPS/TLS做加解密的動作在ELB上面解決，讓EC2 CPU的loading shift出來做該做的事情
- 一般搭配ACM處理

## Route53
- 主要應該會是透過Private Hosted Zone
- 要記得associate VPC，那個VPC才會生效
- 一個VPC只能associate一個Private Hosted Zone
### Alias record
- 有內建health check的功能在裡面，如果record有問題就不會送進去那個ip

### Health check & Failover
> 詹哥說他會

### test record set
- Route53點進去Hosted Zone之後，上面有個地方可以開始測試這個Zone的records

## VPN
### site2site vpn
1. 建立VGW、Attach到VPC
2. 建立CGW、指到對接端口
3. 建立VPN Connection

# Elasticity
## AutoScaling Group
### Launch Template 
### Scaling Policy

## CloudFront
### Cache Behavior
### Error Page
### Validation

## ElastiCache
- 預設下只有單個AZ作用
- Read節點是獨立出來的，解決方法跟Read Replica一樣尬DNS
### Cluster mode or not
- 取決於有沒有要跨ＡＺ部署

## Monitor

## CloudWatch
### Mertic
#### custom
- Cloudwatch agent
#### by second
- 沒弄過，有[文件](https://aws.amazon.com/blogs/aws/new-high-resolution-custom-metrics-and-alarms-for-amazon-cloudwatch/)
### Log
#### custom
- Cloudwatch agent
### Alarm
#### period
- 看要求，不然依據預設Metrics就五分鐘跳一次
### Event
#### schedule, event rule based
- 可以依據事件或是排成觸發Lambda作業

## VPC Flow Log
### format

## Route53 
### Private Host Zone
- 要attach到VPC才會生效
- 一個VPC只能attach一個
### resolution log
> 應該不會出

## CloudTrail
### Filter log and find specific action then alert (SNS)

## Config
### Rule

# Database
## RDS
### Read replica
- https://gitlab.com/ecloudture/olympic/private/use-route-53-with-read-replica-rds-database
### VPC migration
- 換subnet group
### Multi-AZ
### backup & restore
- 可以point-in-time

## DynamoDB
- 我的觀察是通通開on-demand mode下去比較穩
### Global Table
### Capacity mode: on-demand / provisioned
### backup & restore
# Deployment method
## Elastic Beanstalk
## CloudFormation
- https://gitlab.com/ecloudture/olympic/how-to-build-an-elastic-structure/blob/master/lab-network_yaml.yaml
- 
### CloudFormer
1. CloudFormation > Sample > 最下面
2. 餵Username & password
3. 看IAM有沒有權限建立起來，這Template會去建Role，有可能權限被鎖不能用
4. Deploy好之後，透過HTTPS訪問EC2 IP，略過憑證檢查
5. 開始打勾勾，最後一步會吐出Template in JSON
    > 再去CloudFormation Designer裡面轉成yaml比較好看（私心推薦

# Management tools
## System manager
- ec2要attached service role才能call
    > 取決於有沒有IAM權限
### Automation
- 跑腳本的
### State manager
- 可以安排時間跑腳本的
### Session manager
- 可以直接透過console連到那台ec2的
### Parameter store
- 放敏感資訊／參數的

## Trusted advisor
- 如果有權限的話可以加減看看


# CLI

# SDK/API


# 不會出的

```
# Visualization
## Athena
## ElasticSearch
## CloudWatch Dashboard
### mix purchase option with on-demand & spot
## VPN CloudHub
大概知道怎麼接在一起就行
## AWS well-architected tool
## Best practices
# Authentication
## IAM
### Role
### Federation
### Group to manage users
## Cognito
```