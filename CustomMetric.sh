#!/bin/bash
sudo su
yum install sysstat -y
cat > /opt/custom_metrics.sh << EOL
#!/bin/bash
export AWS_ACCESS_KEY_ID=<AWS_ACCESS_KEY_ID>
export AWS_SECRET_ACCESS_KEY=<AWS_SECRET_ACCESS_KEY>
export AWS_DEFAULT_REGION=us-east-1
export AWS_DEFAULT_OUTPUT=json 
USEDMEMORY=\$(free -m | awk 'NR==2{printf "%.2f\\t", \$3*100/\$2 }')
TCP_CONN_PORT_80=\$(netstat -an | grep 80 | wc -l)
IO_WAIT=\$(iostat | awk 'NR==4 {print \$5}')
PROC=\$(grep 'cpu ' /proc/stat | awk '{ print (\$2+\$4)*100/(\$2+\$4+\$5)}')
INSTANCE="`wget -q -O - http://169.254.169.254/latest/meta-data/instance-id || die \"wget instance-id has failed: $?\"`"
aws cloudwatch put-metric-data --region "us-east-1" --metric-name asg-memory-usage --dimensions instance_n=\$INSTANCE --namespace "Custom" --value \$USEDMEMORY
echo "RAM done"
aws cloudwatch put-metric-data --region "us-east-1" --metric-name asg-Tcp_connections --dimensions instance_n=\$INSTANCE   --namespace "Custom" --value \$TCP_CONN_PORT_80
echo "TCP done"
aws cloudwatch put-metric-data --region "us-east-1" --metric-name asg-IO_WAIT  --dimensions instance_n=\$INSTANCE --namespace "Custom" --value \$IO_WAIT
echo "IO done"
aws cloudwatch put-metric-data --region "us-east-1" --metric-name asg-CPU  --dimensions instance_n=\$INSTANCE --namespace "Custom" --value \$PROC
echo "CPU done"
EOL
chmod +x /opt/custom_metrics.sh
echo "*/1 * * * * /opt/custom_metrics.sh" > cronfile
crontab cronfile