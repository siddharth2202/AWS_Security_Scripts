# AWS Security Audit Framework

## Overview

AWS Security Audit Framework is a collection of scripts used to perform security assessments across multiple AWS services.

The framework generates:

* CSV Reports
* HTML Reports
* Optional S3 Report Uploads

The reports help identify security misconfigurations and provide an easy-to-understand view of the AWS environment.

---

# Supported AWS Services

The framework currently supports security audits for the following AWS services:

1. IAM
2. CloudTrail
3. S3
4. EC2
5. Security Groups
6. VPC
7. RDS
8. Lambda
9. EBS
10. CloudFormation
11. CloudWatch
12. AWS Config
13. KMS
14. SNS
15. SQS
16. Secrets Manager
17. ECR
18. ECS
19. EKS
20. GuardDuty
21. Security Hub
22. Macie
23. Route 53
24. Elastic Load Balancer (ALB/NLB)
25. ACM
26. Redshift
27. DynamoDB
28. ElastiCache
29. AWS Organizations
30. Access Analyzer
31. Inspector
32. WAF & Shield
33. AWS Backups

For detailed information about what each service audit checks, see:

```text
SERVICE_DESCRIPTIONS.md
```

---

# Initial Setup

Make all scripts executable:

```bash
chmod +x *.sh
```

Run the bootstrap script:

```bash
./bootstrap.sh
```

The bootstrap script will:

* Verify AWS connectivity
* Create required folders
* Generate configuration files
* Create the report storage bucket (if required)

---

# Running an Audit

Run the desired audit script.

Example:

```bash
./check-iam.sh
```

Additional service scripts follow the same format:

```bash
./check-cloudtrail.sh
./check-s3.sh
./check-ec2.sh
```

---

# Report Location

Generated reports are stored locally in:

```text
reports/
```

Example:

```text
reports/
├── iam-report.csv
└── iam-report.html
```

---

# Report Uploads

If automatic uploads are enabled, reports will also be uploaded to Amazon S3.

The upload location will be displayed after the script completes.

---

# Recommended Usage

For a new environment:

```bash
chmod +x *.sh
./bootstrap.sh
./check-iam.sh
```

For future audits:

```bash
./check-<service>.sh
```

Example:

```bash
./check-s3.sh
./check-cloudtrail.sh
./check-ec2.sh
```

---

# Troubleshooting

If configuration files are missing:

```bash
./bootstrap.sh
```

If script execution fails:

```bash
chmod +x *.sh
```

If report uploads fail:

* Verify AWS permissions
* Verify the S3 report bucket exists

---

# Documentation

Detailed service-level audit descriptions are available in:

```text
SERVICE_DESCRIPTIONS.md
```
