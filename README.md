# 打沙包懶人包
1. 完善架構，看情境盡可能做到Well-Architect
2. 畫架構圖來輔助說明設計概念
3. 包成CloudFormation Template
* 千萬不要為了追求Cost、Latency，而放棄其他層面該做的
* Dashboard分數僅供參考，並不代表真正成績，我們大會會review架構評分：
    * **Security**
    * **Automation**
        * 不管你是要自己寫成一包部署下去
        * 或是Github找template直接deploy之後再改設定
        * ***架構有的設定都要呈現在CloudFormation Resources那邊，才會做為評判標準***
    * Performation
    * Cost

## Default套路 - 標準三層式結構
- 有預設的機器，當中會需要塞UserData拿最新的包，UserData會啟用那個程序開始算分
- 網路上的code都能用
- ***會有support service list，以上面有支援的為主***

### 權限確認
- 不能建立IAM Role，但可以看能利用的權限有哪些
- 如果有給AccessKey，可以透過`aws configure`配置
- list role不知道會不會過，下Command Line看看：`aws iam list-roles --query Roles[*].Arn`，抓一下有什麼Service Roles可以玩
- 當跳出Permission Deny，確認Region是否在允許範圍內、服務能不能用、機器大小或是IAM不能用

### 網路環境確認
- CIDR範圍、切割狀況
- VPC有沒有啟用DNS Resolution
    - Enable DNS resolution
    - Enable DNS hostnames
- SG, NACL, Route Table, Gateway彼此之間的關係
- Enable VPC Flow、推去CloudWatch Logs方便查看

### 起手式：EC2 + AutoScaling + ELB + CloudFront
1. Create空的ElB，Listener設定80，Security Group配置allow HTTP from `0.0.0.0/0`
2. CloudFront指定origin到ELB
    - 都先default cache不用改東西
    - 等到ELB+ASG一切穩定之後再開始測試CloudFront
3. 驗證Instance服務如何運作、是否正常
    - 先理解單台是如何作業的
    - 該配置的套件、相依性
    - 能夠順利乘載流量，先把EC2 Hostname送出去接流量
    - 再寫成UserData
4. 測試、修改user data，建議先尬CloudWatch agent推memory/log出來
    - [看文件照做安裝CloudWatch Agent](https://aws.amazon.com/blogs/aws/new-high-resolution-custom-metrics-and-alarms-for-amazon-cloudwatch/)
5. Create AMI打包EC2 Instance
6. 建立Launch Template/Configuration裡面
    > prefer template if available
    - 指定AMI
    - IAM Role(InstanceProfile)
    - UserData
    > 如果用Configuration，要多設定
    - Instance Type
    - Pricing Model
    - Security Group
    
7. 建立AutoScaling Group
    - 如果Spot不能用，就不用混搭
    - 如有限定Instance Type，也不用混搭
8. 把AutoScaling Group掛進ELB底下的Target Group
9. 設定Cloudwatch Alarm跟ScalingPolicy
    > 預設先設定Target CPU 70%，之後再改
    > Alarm看有沒有需要送email/SMS/HTTP等等，都可以串
10. 塞ELB Endpoint接應流量
    > 不要塞IP出去，用hostname才能真正藏著service endpoint
11. 測試CloudFront是否能正常access服務
    > 在這階段驗證Header, TTL, Cookie, QueryString的配置
12. 換成CloudFront接應流量
13. 監控整體運作狀況，做適當調整

### 監控
- Application有需求要寫Log的話，直接靠CloudWatch Agent推出來
- 靠CloudWatch Metrics, Alarms解決
- 先把有用的Metrics都先配置一輪Alarm
    - CPU above 70%, under 32%
    - Memory above 1.5G
    - Network Traffic 
    - ALB Traffic 
    - ALB RequestCount → 推推，ResponseTime會牽連到DB端，不太準
    - ALB ActiveConnectionCount 
    - ALB HTTPCode_ELB_5XX_Count
    - RDS Connection → 推推
    - RDS CPU
    - ElastiCache Memory
    - ElastiCache CPU
    - DynamoDB R/W情況，如果capacity mode是on-demand就不用管
    - NAT GW 運作狀況，[這邊有範本](https://github.com/widdix/aws-cf-templates/blob/master/vpc/vpc-nat-gateway.yaml)
- 看沙包面板的分數現在是上升或下降
    - 若下降則是Response有異常，檢查服務是否正常運作、或是需要調整capacity
- 看沙包事件，會顯示request/response之間的關係，從而去判定該做哪一段的效能調整
    - EC2 (ASG)
    - ELB
    - Database level
    - Storage
- EBS撞到Disk I/O的話 → 調IOPS
- EFS效能會看使用狀況決定
    - Throughput一般建議使用 ***Bursting mode***，因為Provisioned mode會看使用量（以TB為單位）去調整，用大量空間去換較好的Throughput
    - Performance跟EBS一樣，General Purpose可以解決大部分場景；如果場景I/O相對敏感，建議改為 ***Max I/O***

### 加強安全性
1. Security Group Chain，讓最外面的那個全開就好，符合最小暴露原則
2. 如果同個SG裡面要互通，記得要allow protocol from 自己的sg-id
3. NACL Outbound只開放必要流量
4. Endpoint盡量用
    - S3 Gateway
    - DynamoDB Gateway
    - [CloudWatch Metric Interface](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch-and-interface-VPC.html)
    - [CloudWatch Log Interface](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/cloudwatch-logs-and-interface-VPC.html)
5. S3 Bucket Policy限定[只能透過Endpoint來訪問](https://docs.aws.amazon.com/AmazonS3/latest/dev/example-bucket-policies-vpc-endpoint.html)
    > 當同一個Bucket也要允許Public來訪問的情況下，不適用
6. [AWS WAF](https://docs.aws.amazon.com/solutions/latest/aws-waf-security-automations/architecture.html)也要Deploy上去
    - CloudFront的要放在us-east-1
    - ALB的看region在哪
    - Request rate limit先設定寬鬆一點，檢察單位為同一個IP五分鐘算一次，最小為2000次，先設個一萬或十萬
    
    - Flooding, XSS, SQL Injection, Bad Bot, 黑白名單都可以透過[awslabs/aws-waf-security-automations](https://github.com/awslabs/aws-waf-security-automations)實現
    - https://gitlab.com/ecloudture-dev/blog/aws-waf-test

### 實作Resilient - 滿足HA、Scalability
- 大原則： ***避免單點故障的可能性***
- VPC網路規劃時就要有Multi-AZ的概念，呈現對稱網路
- AutoScaling Group最少兩台機器跨越兩個AZ
- RDS要開Multi-AZ
- ElastiCache要開Cluster mode
- NAT GW一個AZ一個
    > 但route table會變得比較麻煩，自行取捨
- 多用Service List上面的managed services
- DNS Health Check，若服務端點出現問題，自動failover去備援站點
- CloudFront上面可以設定Error Page，假設後方出現4xx/5xx的話，導流去某一個path，ex. error.html，上面寫說網站現正維護中之類的

### RDS
- [Read replica](https://gitlab.com/ecloudture/olympic/private/use-route-53-with-read-replica-rds-database)
    1. 看能不能做Vertical Scale，換Instance Type
        > 八成不能
    2. 讀寫分離，要試看看能不能做，不能的話只能單靠Master
        > 應該會可以搭配ElastiCache處理
    3. 尬Read Replica，要把讀的Endpoint改過來才有用不然還是會在Master上面
        > Application邏輯處理
- 如果有需要做VPC migration，換subnet group就好
- ***Multi-AZ最好要開***
- backup & restore，週期維持預設就好，除非有特別說備份週期、指定備份時間再異動
    > 可以point-in-time restore

### DynamoDB
- Capacity mode: on-demand / provisioned，整體效能取決於這
    > 我的觀察是通通開on-demand mode下去比較穩
    > 如果不給弄，就要尻AutoScaling來調整Capaciry Unitㄌ
- Global Table，僅有Table是空的時候才能建立
- backup & restore
    - Point-in-time Recovery，自動備份、最多35天
    - On-Demand Backup and Restore，完整手動備份

### ElastiCache
- 預設下只有單個AZ作用
    > 有單點故障可能性，要看場景搭配
- Read節點是獨立出來的，解決方法跟Read Replica一樣尬DNS
- Cluster mode or not
    - 取決於有沒有要跨AZ部署

### Deploy Application to ECS 
***＊必先完成上面EC2 level，再來考慮做ECS***
1. 確認EC2 Instance OS是什麼，決定base image from哪個OS
2. 先在local寫dockerfile，驗證Application/UserData有辦法包成Container並順利執行
    > 在每一行bash前面加上`RUN`，若有需要開機運行則是`CMD`，以下為以amazon linux為例，在dockerhub上面可以找到相對應得
    ```
    # 指定Base Image, 從docker hub找
    FROM amazonlinux:1

    # 打包package
    RUN yum update -y
    RUN yum install python34 git curl -y
    RUN curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
    RUN python get-pip.py
    RUN pip install flask
    RUN pip install boto3
    RUN pip install redis
    RUN pip install requests
    RUN cd ~
    RUN git clone https://github.com/KYPan0818/container-easy-http.git

    # 宣告Container對外的Service port，沒指定也沒差，給別人看的
    EXPOSE 80

    # 指定Container開啟後要執行的指令，跟機器開機腳本差不多概念
    CMD echo helloworld
    CMD python --version
    ```
2. 在本機驗證好一切如預期運行，再推上去ECR
> Deploy in EC2，如果用Fargate則可以跳至6
3. 建立ECS Cluster，記得要指定ECS optimized AMI，AMI ID要看[文件](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-optimized_AMI.html)
4. 在UserData上面寫入Cluster name，[文件](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/launch_container_instance.html)
```
#!/bin/bash
echo ECS_CLUSTER=your_cluster_name >> /etc/ecs/ecs.config
```
5. 確認ECS Cluster底下是否有EC2，如果有，再開始建ECS Service
6. 以下參考：https://gitlab.com/ecloudture/aws/aws-ecs-workshop
7. ECS Services預設只針對CPU/Memory去成長，要看情況搭配，或是把container/task custom metrics再丟出來往後處理
- 只有創建ECS Service當下可以mapping到target group，若有變更就要recreate service

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

### Re-Run Userdata after launched EC2
- [Linux](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.htm)
    - 看[Cloud-init](https://cloudinit.readthedocs.io/en/latest/topics/examples.html)文件去修改Service配置黨
    - [Knoledage center有把它改成每次restart後都會重新執行userdata的範例](https://aws.amazon.com/premiumsupport/knowledge-center/execute-user-data-ec2/)
- [Windows](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/ec2-windows-user-data.html)
    - 進去OS找Cloud-Init的服務
        > 或是Cloud Config，有點忘記詳細名稱
    - 當中有一個分頁有個選項可以打勾，要重新跑一次UserData
    - 每次都要再去勾才會生效

### Instance Type
- 看有沒有用對，但八成會限定`t2.micro`
- 不然可以搭配AutoScaling做混搭的request

### Spot Instance / Fleet
> 八成沒權限

### Instance Store
- 要注意一但Stop/Terminated就會消失
- 最好轉存到EBS、CloudWatch Logs上面做長期Store

### EBS
- 容量不夠的話可以直接extend，但不能縮；改完建議做restart完整load進來一次，不要在OS直接調整
- 撞到Disk I/O的話 → 調IOPS
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

## ECS
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

## Lambda with API Gateway
> 如果有特別指定再考慮
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

## S3
- https://gitlab.com/ecloudture/olympic/private/s3-storage-class-lifecycle-policy
- https://gitlab.com/ecloudture/olympic/aws-s3-cors
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

### [LifeCycle Policy](https://gitlab.com/ecloudture-dev/blog/s3-storage-class-lifecycle-policy)


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

### [VPC Flow Log](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html) if needed

## ELB
- 最小deploy需要/27，才能作節點Scale
- Target group的health check機制注意
- keepalive如果有特別說的話再改
### Session
- 看sticky seesion的需求
### Routing Algorithm
- ALB上面可以在每一個listener去針對不同需求下規則，Path/Host/Port導流到不同的target group當中處理
### SSL Termination
- 把HTTPS/TLS做加解密的動作在ELB上面解決，讓EC2 CPU的loading shift出來做該做的事情
- 一般搭配ACM處理

## CloudFormation
- 分層級去看
    - VPC, Subnet, Route, Gateway, SG, NACL, Endpoint
    - EC2, Launch configuration/template, AutoScaling Group, Scaling Policy, CloudWatch Alarm
    > 看需不需要透過cfn-init/userdata，安裝一些套件在EC2
    - IAM Role
    - ELB, Target Group, Listener, Routing Policy
    - RDS, Multi-AZ
    - DynamoDB
    - S3, Bucket Policy, Block public access
    - 有些相關配置要上`Depends On`、Export/Output參數出來的要記住

- 能包的漂亮盡量包，要上註解描述那一區塊在幹嘛
    > 有空的話
- 可以拆掉分別用stack建立 → 相對簡單
- Serverless的部分用SAM去部署比較簡單
- 常用飯粒們  
    - https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-template-resource-type-ref.html
    - https://github.com/awslabs/aws-cloudformation-templates
    - https://github.com/widdix/aws-cf-templates
- Container
    - [pahud/ecs-cfn-refarch](https://github.com/pahud/ecs-cfn-refarch)
    - [aws-samples/amazon-eks-refarch-cloudformation](https://github.com/aws-samples/amazon-eks-refarch-cloudformation)
- 沒什麼用的
    - https://gitlab.com/ecloudture-dev/blog/aws-basic-of-cloudformation
    - https://gitlab.com/ecloudture/olympic/how-to-build-an-elastic-structure/blob/master/lab-network_yaml.yaml
    - https://gitlab.com/ecloudture/aws/ect-course/aws-architecture/tree/master/05-deploy-your-cloudformation-template

### CloudFormer
1. CloudFormation > Sample > 最下面
2. 餵Username & password
3. 看IAM有沒有權限建立起來，這Template會去建Role，有可能權限被鎖不能用
4. Deploy好之後，透過HTTPS訪問EC2 IP，略過憑證檢查
5. 開始打勾勾，最後一步會吐出Template in JSON
    > 再去CloudFormation Designer裡面轉成yaml比較好看（私心推薦

## Route53
- 主要應該會是透過Private Hosted Zone
- 要記得associate VPC，那個VPC才會生效
- 一個VPC只能associate一個Private Hosted Zone
### Alias record
- 有內建health check的功能在裡面，如果record有問題就不會送進去那個ip

### Health check & Failover
- https://gitlab.com/ecloudture-dev/aws/multi-region-failover-with-amazon-route53

### test record set
- Route53點進去Hosted Zone之後，上面有個地方可以開始測試這個Zone的records

## VPN
### site2site vpn
1. 建立VGW、Attach到VPC
2. 建立CGW、指到對接端口
3. 建立VPN Connection
- https://gitlab.com/ecloudture/aws/ect-course/aws-architecture/tree/master/03-vpn-connection

## AutoScaling Group
- https://gitlab.com/ecloudture/aws/ect-course/aws-architecture/tree/master/04-elastic-your-architecture
### Launch Template 
### Scaling Policy

## CloudFront
### Cache Behavior
### Error Page
### Validation

## CloudWatch
### Mertic
#### custom
- Cloudwatch agent
- [有文件照做就會跑出來](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/publishingMetrics.html)
- 要注意權限
#### by second
- 沒弄過，有[文件](https://aws.amazon.com/blogs/aws/new-high-resolution-custom-metrics-and-alarms-for-amazon-cloudwatch/)
### Log
#### custom
- Cloudwatch agent
- 要注意權限
### Alarm
#### period
- 看要求，不然依據預設Metrics就五分鐘跳一次
### Event
#### schedule, event rule based
- 可以依據事件或是排成觸發Lambda作業

## Route53 
### Private Host Zone
- 要attach到VPC才會生效
- 一個VPC只能attach一個
### resolution log
> 應該不會出

## CloudTrail
### Filter log and find specific action then alert (SNS)
- [結合Athena的範例](https://gitlab.com/ecloudture-dev/blog/posted/querying-cloudtrail-logs-with-aws-athena)

## Config
### [Custom Rule](https://docs.aws.amazon.com/config/latest/developerguide/evaluate-config_develop-rules.html)
- 或是參考[awslabs/aws-config-rules](https://github.com/awslabs/aws-config-rules)

## Elastic Beanstalk
- 微乎其微的出現率

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


## [CLI](https://aws.amazon.com/cli/)


## SDK/API
- [boto3](https://boto3.amazonaws.com/v1/documentation/api/latest/index.html)，左邊Available Services點下去找對應服務

## 不會出的（吧

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