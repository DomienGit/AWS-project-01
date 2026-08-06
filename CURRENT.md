# Handoff - DevOps AWS 3-tier deployment (Java-Login-App)

Ostatnia aktualizacja: 2026-08-06 20:25 | PC: domiendev-System-Product-Name | repo: /home/domiendev | branch: N/A (katalog nie jest git repo)

## Co zostało zrobione
- Skonfigurowane AWS Free Tier w regionie `eu-central-1` (Frankfurt)
- Utworzona instancja bazowa EC2 `golden-ami-base` (`i-0edf992d3a725ccd7`) z IAM role `devops-ec2-role` (CloudWatchAgentServerPolicy + AmazonSSMManagedInstanceCore) na Amazon Linux 2023, t3.micro
- Zainstalowane agenty na bazowej EC2: CloudWatch Agent, SSM Agent (preinstalowany), custom mem-metric skrypt przez systemd (IMDSv2, region eu-central-1)
- **3 Golden AMI gotowe:** `nginx-golden` (Nginx + CW Agent + mem-metric), `tomcat-golden` (Tomcat 9.0.93 + Java 17 Corretto + systemd), `maven-golden` (Maven 3.9.9 + Java 17 + Git)

## W trakcie (gdzie stanęło)
- Koniec sekcji "Create Golden AMIs" z zadania. AMI wszystkie dostępne (status `available`)
- Trzy instancje bazowe wciąż running — można je terminate jak AMI gotowe (lub zostawić na debugging)
- **Nie ma jeszcze lokalnego repo git** — żadnych skryptów nie versionujemy, wszystkie komendy tylko w historii chatu

## Następne kroki
1. **VPC Deployment** — stworzyć 2 własne VPC (`192.168.0.0/16` + `172.32.0.0/16`), public/private subnety, NAT Gateway, Internet Gateway, Transit Gateway, route tables
2. **Bastion Host Setup** — instancja w public subnet, nowy SG z SSH
3. **Maven Build** — odpalić instancję z `maven-golden` AMI, sklonować Java-Login-App repo, zaktualizować pom.xml (SonarCloud + JFrog), uruchomić `mvn clean install`, wrzucić `.war` do JFrog
4. **3-Tier Architecture** — RDS MySQL, Tomcat ASG (z `tomcat-golden`), Nginx ASG (z `nginx-golden`), 2x NLB (publiczny + prywatny)
5. **Application Deployment** — user-data skrypty pobierające `.war` z JFrog, schema SQL do MySQL
6. **Post-Deployment** — cron S3 dla Tomcat logów, CloudWatch alarmy

## Pliki dotknięte w sesji
- `/home/domiendev/.handoff/CURRENT.md` (ten plik)
- **Na CloudShell:** `~/.ssh/devops-key.pem` (klucz prywatny), `~/devops-vars.sh` (zmienne: INSTANCE_ID, PUBLIC_IP, SG_ID, VPC_ID, SUBNET_ID, AMI_ID, AMI_NGINX_ID, AMI_TOMCAT_ID, AMI_MAVEN_ID, TOMCAT_INSTANCE_ID, MAVEN_INSTANCE_ID)
- **Na EC2 golden-ami-base:** `/usr/local/bin/mem-metric.sh`, `/etc/systemd/system/mem-metric.service`, `/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json`
- **Na EC2 tomcat-base:** `/etc/systemd/system/tomcat.service`, `/opt/tomcat/` (symlink do `/opt/apache-tomcat-9.0.93`)
- **Na EC2 maven-base:** `/opt/maven/`, `/etc/profile.d/maven.sh`

## Niecommitowane zmiany w repo
- N/A — katalog `/home/domiendev` nie jest git repo. Wszystkie skrypty istnieją tylko jako komendy w historii rozmowy. Rozważ `git init` + strukturę `scripts/`, `configs/`, `.gitignore` (z `*.pem`, `devops-vars.sh`, `.aws/`).

## Niestandardowy kontekst / decyzje
- **Region:** `eu-central-1` (zadanie mówi `us-east-1` ale user fizycznie w EU)
- **OS:** Amazon Linux 2023 (nie AL2 jak w zadaniu) — implikuje: `dnf` zamiast `yum`, brak `amazon-linux-extras`, Java 17 Corretto zamiast `java-11-openjdk-devel`, **IMDSv2 wymagane** (IMDSv1 zwraca puste)
- **Instance type:** `t3.micro` (Free Tier w eu-central-1, nie `t2.micro`)
- **Wersje softu:** Tomcat 9.0.93 (nie 9.0.53 — stara niedostępna), Maven 3.9.9 (nie 3.8.4)
- **User preferuje edukacyjne tłumaczenia po polsku**, pyta "dlaczego" — tłumacz logikę nie tylko daj komendy
- **CloudShell IP zmienia się po resecie sesji** — trzeba dodać nowy do SG (`authorize-security-group-ingress`) przed SSH
- **Public IP EC2 zmienia się po stop/start** — zawsze pobieraj na nowo przez `describe-instances`
- **SG `devops-sg` ma otwarte:** port 22 z kilku IP (CloudShell x2, lokalny PC), port 80 (`0.0.0.0/0`), port 8080 (`0.0.0.0/0`)
- **UWAGA KOSZTY:** NAT Gateway i Transit Gateway NIE są Free Tier (~$32/miesiąc + transfer) — usuń po skończeniu zadania. Public IPv4 = ~$3.60/miesiąc/instancję. Stopuj instancje na noc (`aws ec2 stop-instances --instance-ids ...`).
- **AWS account ID:** `905882745860` (widoczne w screenshot SG)
- **Java-Login-App repo:** user ma fork na swoim GitHub (jeszcze nie sklonowany)
- **SonarCloud + JFrog:** konta założone, tokeny wygenerowane (jeszcze nie użyte w Maven build)
