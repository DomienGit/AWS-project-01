# Handoff - 3-tier AWS project (VPC + Bastion)

Ostatnia aktualizacja: 2026-08-07 08:47 | PC: domien-Aspire-A315-51 | branch: (brak repo git)

## Co zostało zrobione
- **Sieć VPC gotowa**: 2 VPC (`192.168.0.0/16` app, `172.32.0.0/16` drugie) + subnety (PUB1/PRIV1/PUB2/PRIV2 w us-east-1a) + IGW ×2 + NAT GW ×2 + Elastic IP ×2 + route tables (publiczne przez IGW, prywatne przez NAT) + Transit Gateway + 2 attachment-y + trasy TGW w RT (VPC1<->VPC2)
- **Security Groups gotowe** z referencjami kaskadowymi: BastionSG (22 z MY_IP/32), NginxSG (80/443 z 0.0.0.0/0, 22 z BastionSG), TomcatSG (8080 z NginxSG, 22 z BastionSG), DB_SG (3306 z TomcatSG)
- **AMI (Nginx/Tomcat/Maven) już istnieją** na koncie; template instances po `create-image` zrobione `terminate`
- **Bastion EC2 stworzony**: BASTION_ID + BASTION_IP zapisane w `devops-vars.sh` na instancji
- **devops-vars.sh na instancji**: funkcja `savevar` + auto-ładowanie przez `.bashrc`; wszystkie ID-ki (VPC1/2, subnety, IGW, NAT, RT, TGW, SG, AMI, KEY_NAME, BASTION_ID, BASTION_IP)

## W trakcie (gdzie stanęło)
- Próba SSH z **laptopa** do bastionu — 2 błędy:
  1. `MyKeyPair.pem not accessible: No such file` — zła ścieżka lub brak pliku na laptopie
  2. `$BASTION_IP` pusty na laptopie (zmienna żyje tylko na instancji w `~/devops-vars.sh`)
- Nie udało się wejść na bastion z laptopa

## Następne kroki
1. Na laptopie: `find ~ -name "*.pem"` — znajdź key pair
2. Na instancji (przez dotychczasowe SSH): `echo $BASTION_IP` — skopiuj IP
3. Na laptopie: `ssh -i /pełna/ścieżka/MyKeyPair.pem ec2-user@<SKOPIOWANE_IP>`
4. Po wejściu na bastion → tworzymy **RDS MySQL** (DatabaseSG gotowy, DB subnet group + instancja)
5. Potem: Tomcat ASG + private NLB (z TOMCAT_AMI), Nginx ASG + public NLB (z NGINX_AMI)
6. Deploy: WAR z JFrog do Tomcat, schema do RDS
7. Post-deploy: CloudWatch, cron logów do S3, alarmy

## Pliki dotknięte w sesji
- `~/devops-vars.sh` NA INSTANCJI (nie na laptopie) — wszystkie ID-ki + funkcja savevar
- `/home/domien/.claude/projects/-home-domien/memory/*.md` — memory Claude (user_learning_devops.md, feedback_no_local_aws.md, MEMORY.md)

## Niecommitowane zmiany w repo
- N/A — `/home/domien` nie jest repozytorium git; memory files są w `.claude/` poza kontrolą wersji

## Niestandardowy kontekst / decyzje
- **Region**: us-east-1
- **2 maszyny w grze**: laptop (ten PC) + instancja EC2 przez SSH. Komendy AWS **odpalane z instancji** (ma IAM rolę), NIE z laptopa. `devops-vars.sh` żyje **tylko na instancji**.
- **Koszty!** TGW ($36) + 2 attach ($72) + 2 NAT GW ($66) = **~$170/miesiąc burn rate** jak zostawić włączone. Budget alert w AWS Console → Billing → Budgets ($5) — KONIECZNIE.
- Project: 3-tier Java Login App (Nginx frontend + Tomcat backend + Maven build + RDS MySQL), repo Java-Login-App, SonarCloud + JFrog Cloud skonfigurowane
- User: uczy się DevOps/AWS, komunikacja po polsku, **sam odpala wszystkie komendy** (nie odpalaj za niego — instrukcja + tłumaczenie "dlaczego")
- Key pair: `MyKeyPair` (prawdopodobnie — potwierdź przez `aws ec2 describe-key-pairs`); .pem gdzieś na laptopie
- Loop: przyszłe sesje zacznij od `/handoff load` po pobraniu tego pliku na PC2
