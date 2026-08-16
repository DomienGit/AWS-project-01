# Handoff - Faza 4 DONE, Faza 5 (Tomcat/Nginx) wstrzymana przed ASG

Ostatnia aktualizacja: 2026-08-16 21:01 | PC: domiendev-System-Product-Name | branch: main

## Stan (co ważne na start nowej sesji)
- **Faza 4 KOMPLETNA**: build + Sonar + **WAR w JFrog** → `https://trialrk1nii.jfrog.io/artifactory/maven-snapshots-libs-snapshot/com/devopsrealtime/dptweb/1.0-SNAPSHOT/dptweb-1.0-SNAPSHOT.war` (auth: JFrog user + Access Token; `<id>snapshots</id>` łączy pom↔settings.xml)
- **Faza 5 częściowa**: subnet 1b ✅, RDS ✅, schema UserDB.Employee ✅, Bastion ✅. **Tomcat ASG/NLB/TG/LT — NIE tworzone** (przygotowane komendy, nie odpalone). Nginx tier — nie ruszany.
- **Teardown wykonany na końcu sesji** (RDS + EC2 + teardown.sh) → koszt ~$0. Zostały tylko golden AMI.
- recreate.sh — **2 bugi naprawione w repo** (TGW poll loop, 1 subnet/AZ). Niecommitowane!

## Plan wznowienia (dokładna kolejność)
1. CloudShell: `source ~/devops-vars.sh` (AMI/KEY_NAME tam), region **eu-central-1**, stwórz subnet `192.168.11.0/24` eu-central-1b (RDS wymaga 2 AZ) + assocjuj z PRIV_RT1
2. `./recreate.sh` (naprawiony; spyta o IP laptopa → wcześniej `curl ifconfig.me` z laptopa). **Po recreate dodaj brakującą regułę**: `authorize-security-group-ingress` 22/tcp z `$MY_IP` na `$BASTION_SG` (ostatnim razem ta reguła nie weszła przy recreate — SSH wiecznie wisiał). MavenSG/Maven EC2 **niepotrzebne** (WAR jest w JFrog)
3. RDS: `create-db-subnet-group` (PRIV1+PRIV1B) + `create-db-instance app-db` db.t3.micro admin/**Admin123** — wersję wybrać przez `describe-db-engine-versions` (8.0.33 NIE istnieje w eu-central-1) + `wait` + `savevar DB_ENDPOINT`
4. Schema (z Bastionu, bo Maven EC2 nie istnieje): temp otwórz DB_SG 3306 z BastionSG → `sudo dnf install -y mariadb105` (AL2023, **nie ma amazon-linux-extras**) → `CREATE DATABASE UserDB; CREATE TABLE Employee (id INT AUTO_INCREMENT PRIMARY KEY, first_name VARCHAR(50), last_name VARCHAR(50), email VARCHAR(100), username VARCHAR(50), password VARCHAR(255), regdate DATE);` → revoke
5. Bastion: `run-instances` z `$MAVEN_AMI`, t2.micro, `$BASTION_SG`, `$PUB1_ID`, public IP → SSH z laptopa z `-A`
6. Tomcat (komendy A-E z historii): `~/tomcat-userdata.sh` w CloudShell przetrwał, ale ma **stary DB_ENDPOINT** → wygeneruj od nowa (setenv.sh ze SPRING_DATASOURCE_URL/USERNAME/PASSWORD — env przesłania application.properties z endpointem autora; WAR jako ROOT.war) → LT ($TOMCAT_AMI) → TG TCP 8080 → internal NLB w PRIV1 → ASG min1 max2
7. Nginx: LT ($NGINX_AMI + user-data reverse proxy → DNS internal NLB) → TG → **publiczny NLB w PUB1** → ASG
8. Test: rejestracja w appce → `SELECT * FROM UserDB.Employee`

## Fixy pom.xml forka (przy każdym fresh clone — NIE commitnięte do forka!)
1. wersja `1.0`→`1.0-SNAPSHOT` 2. usuń `<repositories>`/`<pluginRepositories>` z `edshopdpt8.jfrog.io` (JFrog autora — zwraca HTML i truje ~/.m2) 3. `<version>8.0.33</version>` dla mysql-connector-java 4. `<distributionManagement>` (trialrk1nii) 5. settings.xml TYLKO servers+`<pluginGroups>org.sonarsource.scanner.maven</pluginGroups>` 6. sonar.* properties 7. **nie edytować** application.properties (override env). Pełna lista też w pamięci Claude (project_faza4_maven.md)

## Pliki dotknięte / niecommitowane
- `scripts/recreate.sh` (fix TGW) — zmodyfikowany, do zcommitowania razem z tym handoffem
- `.handoff/CURRENT.md` (ten plik)

## Środowisko wykonania
- AWS → CloudShell (eu-central-1) | SSH → laptop (.pem, user `ec2-user`, AMI = AL2023)
- App: Spring Boot 2.7.18 + JSP, czysty JDBC (SQL injection w kodzie — świadomie zostawiamy)

## Decyzje z sesji
- Pauza kosztowa przed Nginx tierem (teardown = $0)
- DB config przez env (setenv.sh) zamiast rebuild WAR; WAR jako ROOT.war (kontekst /)
- Fixy forka nie commitowane (user zrezygnował z PAT) — odtwarzane ręcznie wg listy wyżej

## Do sprawdzenia przed startem
- `git pull` na PC | region CloudShell | devops-vars.sh ma AMI+KEY_NAME | .pem na laptopie | IP laptopa (`curl ifconfig.me`) | JFrog user+token pod ręką (potrzebny do user-data Tomcata)

## Stały kontekst
- 3-tier Java Login App (Nginx+Tomcat+RDS), fork prodevopsguy, folder DevOps-Project-01/Java-Login-App
- User sam odpala komendy (jednolinijkowce!), komunikacja PL. Przyszłe sesje: `/handoff load` po `git pull`
