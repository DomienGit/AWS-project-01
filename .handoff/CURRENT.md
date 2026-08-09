# Handoff - 3-tier AWS project (Maven EC2 live, przed pom.xml update)

Ostatnia aktualizacja: 2026-08-09 13:34 | PC: domiendev-System-Product-Name | branch: main

## Co zostało zrobione
- **`recreate.sh` poprawione (częściowo)**: `MY_IP` teraz pyta usera (linia 201-204). **2 bugi wciąż w skrypcie** — patrz sekcja "Do naprawienia w recreate.sh".
- **Recreate wykonany**: kroki 1-7 (VPC1/2, IGW1/2, subnety, EIP, NAT GW, RT, TGW) przeszły OK. Kroki 8/9/10 (TGW attachments, TGW routes, SG) wykonane **RĘCZNIE** poprawionymi komendami (opis w Decyzjach).
- **Security Groups gotowe**: BastionSG, NginxSG, TomcatSG, DB_SG, **MavenSG** (dodatkowy, nie w skrypcie — out: 22 z `$MY_IP`).
- **Maven EC2 stworzony**: `$MAVEN_ID`, `$MAVEN_IP` zapisane w `devops-vars.sh`. AMI=`$MAVEN_AMI` (ami-0cd7aa79b367b68df7), t2.micro, w `$PUB1_ID`, public IP, MavenSG.
- **SSH na Maven EC2 działa**: z laptopa przez `ssh -i /ścieżka/MyKeyPair.pem ec2-user@$MAVEN_IP`. Username = `ec2-user` (Amazon Linux 2).
- **Repo sklonowane na Maven EC2** przez **sparse checkout**: tylko folder Project-1 z forka `Devops-Projects`.

## W trakcie (gdzie stanęło)
- **User odpala teardown.sh teraz** — Maven EC2 i cała infra będą zniszczone. Repo na EC2 znika z instancją.
- **Update `pom.xml` (JFrog + SonarCloud properties) i `settings.xml` (JFrog creds) — NIE ZROBIONE**. To następny konkretny krok po ponownym rebuild'cie.

## Następne kroki
Po teardown, na nowej sesji:
1. **Odpal `recreate.sh`** (uwaga na 2 bugi — patrz niżej). Kroki 1-7 OK. Po błędzie w kroku 7 (TGW wait) wykonaj ręcznie poprawione komendy z tej historii:
   - **TGW attachments** (1 subnet per AZ): `--subnet-ids $PUB1_ID` (nie `$PUB1_ID $PRIV1_ID`)
   - **Poll loop** zamiast `aws ec2 wait transit-gateway-available`
   - **TGW routes** (4 komendy, CIDR hardcoded: 192.168.0.0/16 ↔ 172.32.0.0/16)
   - **Security Groups** (BastionSG, NginxSG, TomcatSG, DB_SG) + **MY_IP prompt**
2. **Stwórz MavenSG** (out: 22 z `$MY_IP`): `aws ec2 create-security-group --group-name MavenSG --vpc-id $VPC1_ID ...` + authorize 22 z `$MY_IP`
3. **Stwórz Maven EC2** (`$MAVEN_AMI`, t2.micro, MavenSG, `$PUB1_ID`, public IP) → `$MAVEN_ID`, `$MAVEN_IP`
4. **Czekaj na running**, zapisz public IP: `aws ec2 wait instance-running ... && savevar MAVEN_IP ...`
5. **SSH z laptopa**: `ssh -i /ścieżka/MyKeyPair.pem ec2-user@$MAVEN_IP`
6. **Sparse checkout repo na Maven EC2**:
   ```bash
   git clone --sparse --filter=blob:none https://github.com/<USER>/Devops-Projects.git
   cd Devops-Projects
   git sparse-checkout set "<FOLDER_PROJECT_1>"
   ```
7. **TUTAJ KONTYNUUJ**: update `pom.xml` (JFrog `<distributionManagement>` + SonarCloud `<sonar.*>` properties), stwórz `settings.xml` (JFrog creds), `mvn clean install -s settings.xml`, `mvn sonar:sonar -Dsonar.login=<TOKEN>`
8. Po buildzie: terminate Maven EC2, dalej Faza 5 (RDS + Tomcat ASG/NLB + Nginx ASG/NLB + Bastion)

## Do naprawienia w `scripts/recreate.sh` (nie zrobione w tej sesji)
1. **Linia 169**: `aws ec2 wait transit-gateway-available` → **nie istnieje** w CLI na CloudShell. Zamienić na **poll loop** (jak w teardown.sh dla NAT GW).
2. **Linia 174, 179**: `--subnet-ids "$PUB1_ID" "$PRIV1_ID"` → błąd `DuplicateSubnetsInSameZone` (oba w eu-central-1a). Zamienić na **1 subnet per attachment**: `--subnet-ids "$PUB1_ID"` i `--subnet-ids "$PUB2_ID"`.

## Pliki dotknięte w sesji
- `.handoff/CURRENT.md` (ten plik)
- `.claude/skills/handoff/SKILL.md` (rozbudowany: 3 nowe sekcje template + Krok 2.5 "pokaż userowi przed zapisem")
- `scripts/recreate.sh` (MY_IP → ręczny prompt, linia 201-204)

## Niecommitowane zmiany w repo
- Wszystkie powyższe pliki zmodyfikowane. Sprawdź `git status` przed kontynuacją.

## Środowisko wykonania
- **Komendy AWS → CloudShell** (IAM creds konta + `~/devops-vars.sh` w persistent home)
- **SSH na EC2 → z laptopa** przez `.pem` (`.pem` zostaje na laptopie, nie wgrywany do CloudShell)
- **Region: eu-central-1** (Frankfurt). Tutorial oryginalnie us-east-1.
- **`MY_IP` w recreate.sh** — skrypt pyta usera o IP laptopa. Sprawdź IP z laptopa: `curl ifconfig.me` (NIE z CloudShell).
- **Architektura single-AZ** (eu-central-1a). TGW attachments: 1 subnet per AZ (publiczny).
- **Koszty**: TGW $36 + 2 attach $11 + 2 NAT GW $64 = **~$111/mc burn** po recreate. Po teardown = $0 (zostają tylko AMI).

## Decyzje z sesji
- **Maven EC2 w PUB1 z bezpośrednim SSH z laptopa** (bez Bastiona). Bastion dopiero w Fazie 5 dla Tomcat/Nginx w private subnet.
- **Sparse checkout** zamiast pełnego klona — oszczędność pobierania (10 projektów w forku).
- **Teardown po każdej sesji** — user kontroluje koszty.
- `/compact` odrzucony jako metoda handoffu między PC.
- **MavenSG dodatkowy** (out: 22 z `$MY_IP`) — nie w recreate.sh, trzeba tworzyć ręcznie po każdym recreate.

## Do sprawdzenia przed startem (prerequisites)
- Region CloudShell = **eu-central-1** (prawy górny róg konsoli AWS)
- `~/devops-vars.sh` w CloudShell zawiera: `$MAVEN_AMI` (ami-0cd7aa79b367b68df7), `$NGINX_AMI` (ami-0040bafdddb56f516), `$TOMCAT_AMI` (ami-0f92780ff09e6df82), `$KEY_NAME`
- Sprawdź: `grep -E 'AMI|KEY_NAME' ~/devops-vars.sh`
- `.pem` keypaira `MyKeyPair` dostępny na laptopie (ścieżka znana)
- IP laptopa: `curl ifconfig.me` z laptopa (będziesz musiał podać w prompcie recreate.sh)
- `git pull` zrobiony na PC (jeśli handoff zmieniał się na drugiej maszynie)

## Stały kontekst (nie zmienia się między sesjami)
- Project: 3-tier Java Login App (Nginx + Tomcat + Maven + RDS), repo `Devops-Projects` (fork prodevopsguy), folder Project-1.
- Stack: Java 11, Tomcat 9.0.53, Maven 3.8.4, Nginx 1.12, MySQL. SonarCloud + JFrog Cloud skonfigurowane (creds u usera).
- User: uczy się DevOps/AWS, komunikacja po polsku, **sam odpala komendy** (instrukcja + tłumaczenie "dlaczego").
- Loop: przyszłe sesje zacznij od `/handoff load` po `git pull` na PC.
