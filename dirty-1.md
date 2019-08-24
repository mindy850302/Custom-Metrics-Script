# 髒東西
![](https://i.imgur.com/lKJsEbo.png)

### 測試EC2當中的Application如何運作
- 依據需求在單機上安裝相關套件
- 寫成UserData

#### UserData
- 自動 mount efs, 安裝 redis 與 MySQL
```
#!/bin/bash
sleep 30
	    
# EFS Setting.
mkdir -p /mnt/efs
echo "<efs-id>:/ /mnt/efs efs tls,_netdev" >> /etc/fstab
mount -a -t efs defaults

# Enable EPEL Repository and install and start Redis locally.
sed -i 's/enabled=0/enabled=1/g' /etc/yum.repos.d/epel.repo
yum -y install wget redis
sleep 5
service redis start
chkconfig redis on

# Download sample applicaiton files.
wget <Application_Endpoint>
mv <Package> <Target_Path>

# Download the latest version of the applicaiton files.
wget <Application_Endpoint>
mv <Package> <Target_Path>

# Path最好是直接指絕對路徑：/home/ec2-user

# Configure and deploy MySQL
yum install mysql
service mysql start
chkconfig mysql on

# Rename and execute files 

mv <Target_Path> server
chmod +x server
./server

# Reboot if the server application crashes
shutdown -h now
```

### CloudFormation部署
- VPC先建，再弄ASG，接著再Deploy其他的
- 記得改裡面的參數為貼近實際狀況
- 其他的就從Sample裡面Deploy出來，再改設定符合情境
- 飯粒們  
    - https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-template-resource-type-ref.html
    - https://github.com/awslabs/aws-cloudformation-templates
    - https://github.com/widdix/aws-cf-templates
- Container
    - [pahud/ecs-cfn-refarch](https://github.com/pahud/ecs-cfn-refarch)
    - [aws-samples/amazon-eks-refarch-cloudformation](https://github.com/aws-samples/amazon-eks-refarch-cloudformation)