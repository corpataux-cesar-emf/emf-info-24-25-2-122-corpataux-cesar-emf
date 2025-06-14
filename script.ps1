﻿# =================================================================================
# Auteur      : Corpataux César
# Date        : 2025-06-05
# Version     : 5.9
# Description : Gestion des tireurs, concours, résultats, logs, accès 100% FTP, interface console complète
# Paramètres  : -UserName
# ==========================================================================

# Paramètres d'entrée
param(
    [string]$UserName = $env:USERNAME # Utilise le nom d'utilisateur du système par défaut
)

Write-Output "Nom de l'utilisateur : $UserName"
Write-Host "Appuyez sur ENTREE pour continuer..." -ForegroundColor Red
Read-Host


chcp 65001 > $null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8




# récupération des paramètres FTP depuis un fichier texte pour éviter de les stocker en clair dans le script
$ftpParams = Get-Content "UserPassword_FTP.txt"
# atribution des paramètres FTP
$ftpBaseUrl = $ftpParams[0]
$ftpUsername = $ftpParams[1]
$ftpPassword = $ftpParams[2] | ConvertTo-SecureString -AsPlainText -Force
# création de l'objet PSCredential pour l'authentification FTP
# PSCredential permet de stocker les informations d'identification de manière sécurisée
$ftpCredential = New-Object System.Management.Automation.PSCredential($ftpUsername, $ftpPassword)

# création du répertoire temporaire local pour stocker les fichiers CSV et logs
$localTempPath = "$env:TEMP\ftp_tireurs"
if (-not (Test-Path $localTempPath)) { New-Item -Path $localTempPath -ItemType Directory | Out-Null }
# -ItemType Directory crée un dossier s'il n'existe pas
# Out-Null supprime la sortie de la commande pour éviter d'encombrer la console

# définition des chemins des fichiers CSV et logs
$tireursFile = Join-Path $localTempPath "tireurs.csv"
$concoursFile = Join-Path $localTempPath "concours.csv"
$recompensesFile = Join-Path $localTempPath "recompenses.csv"
$resultatsFile = Join-Path $localTempPath "resultats.csv"
$logInfoFile = Join-Path $localTempPath "log_info.txt"
$logErrorFile = Join-Path $localTempPath "log_error.txt"


# fonction pour écrire dans les logs
function Write-Log {
    param([string]$type, [string]$msg)
    # les paramètres $type est le type de log (INFO ou ERROR) et $msg le message à enregistrer

    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $type - $msg"
    $logPath = if ($type -eq 'ERROR') { Join-Path $localTempPath "log_error.txt" } else { Join-Path $localTempPath "log_info.txt" }
    Add-Content $logPath $entry
    # Renvoie le fichier log sur le serveur FTP
    Send-File -localPath $logPath -remoteName ([IO.Path]::GetFileName($logPath))
}
# fonction pour envoyer un fichier local vers le serveur FTP
# pas de moi
function Send-File {
    param([string]$localPath, [string]$remoteName)
    $url = [uri]::EscapeUriString("$ftpBaseUrl/$remoteName")
    $client = New-Object Net.WebClient
    $client.Credentials = $ftpCredential
    try {
        $client.UploadFile($url, "STOR", $localPath)
    }
    catch {
        Write-Log ERROR "Échec de l'envoi FTP de $remoteName : $($_.Exception.Message)"
    }
}

# fonction pour recevoir un fichier CSV depuis le serveur FTP
# pas de moi
function Receive-CsvFile {
    param([string]$fileName)
    $local = Join-Path $localTempPath $fileName
    $remote = "$ftpBaseUrl/$fileName"
    $client = New-Object Net.WebClient
    $client.Credentials = $ftpCredential
    try {
        $client.DownloadFile($remote, $local)
        Write-Log INFO "$fileName téléchargé."
    }
    catch {
        New-Item $local -ItemType File -Force | Out-Null
        Write-Log INFO "$fileName créé localement (absent distant)."
    }
}


# fonction pour confirmer l'existence d'un fichier CSV local et y ajouter un header si nécessaire
# pas de moi
function Confirm-CsvFile {
    param([string]$fileName, [string]$header)
    $local = Join-Path $localTempPath $fileName
    if (-not (Test-Path $local -PathType Leaf) -or ((Get-Content $local).Length -eq 0)) {
        $header | Out-File $local -Encoding UTF8
        Write-Log INFO "$fileName initialisé avec header."
        Send-File -localPath $local -remoteName $fileName
    }
}

# fonction pour recevoir tous les fichiers CSV et logs depuis le serveur FTP
# pas de moi
function Get-All {
    Receive-CsvFile "tireurs.csv"
    Receive-CsvFile "concours.csv"
    Receive-CsvFile "recompenses.csv"
    Receive-CsvFile "resultats.csv"
    Receive-CsvFile "log_info.txt"
    Receive-CsvFile "log_error.txt"
    Confirm-CsvFile "tireurs.csv"     "NumeroFusil,Nom,Prenom,DateNaissance,NumeroAVS,Telephone,Email,Adresse,NPA,Ville,DateInscription"
    Confirm-CsvFile "concours.csv"    "NomConcours,DateCreation"
    Confirm-CsvFile "recompenses.csv" "NomConcours,TitreRecompense,Seuil"
    Confirm-CsvFile "resultats.csv"   "NumeroFusil,NomConcours,Score,Recompense,Date"
    if (-not (Test-Path $logInfoFile)) { New-Item $logInfoFile -ItemType File | Out-Null }
    if (-not (Test-Path $logErrorFile)) { New-Item $logErrorFile -ItemType File | Out-Null }
    Write-Host "Fichiers Actualisé " -ForegroundColor Green
    Start-Sleep -Seconds 1
}


# fonction pour sauvegarder un fichier local vers le serveur FTP
# pas de moi
function Save-File {
    param([string]$filePath)
    $fileName = [IO.Path]::GetFileName($filePath)
    Send-File -localPath $filePath -remoteName $fileName
}

# fonction pour ajouter un tireur
function Add-Tireur {
    $csv = Import-Csv $tireursFile
    do {
        #demande le numéro de fusil
        $numero = Read-Host "Numéro de fusil"
        #vérifie si le numéro est déjà utilisé
        if ($csv.NumeroFusil -contains $numero) {
            Write-Host "Déjà existant." -ForegroundColor Yellow
            Write-Log ERROR "Tireur $numero déjà existant."
            $retry = Read-Host "Essayer un autre numéro ? (oui/non)"
            # demande si on veut réessayer avec un autre numéro
            # si oui, on recommence la boucle
            # si non, on sort de la boucle
        }
        else {
            $retry = "non"
            $tireur = [PSCustomObject]@{
                # PSCustomObject permet de créer un objet personnalisé avec des propriétés
                NumeroFusil     = $numero
                Nom             = Read-Host "Nom"
                Prenom          = Read-Host "Prénom"
                DateNaissance   = Read-Host "Date de naissance (YYYY-MM-DD)"
                NumeroAVS       = Read-Host "Numéro AVS"
                Telephone       = Read-Host "Téléphone"
                Email           = Read-Host "Email"
                Adresse         = Read-Host "Adresse"
                NPA             = Read-Host "NPA"
                Ville           = Read-Host "Ville"
                DateInscription = Get-Date -Format 'yyyy-MM-dd'
            }
            # on rajoute ce tireur au CSV des tireurs
            # += ajoute un nouvel objet à parmis les autres
            $csv += $tireur
            # -NoTypeInformation permet de ne pas inclure les informations de type dans le fichier CSV
            # les informations de type sont les noms des propriétés de l'objet
            $csv | Export-Csv -NoTypeInformation -Encoding UTF8 $tireursFile
            Save-File $tireursFile
            Write-Log INFO "Tireur $($tireur.Prenom) $($tireur.Nom) ajouté."
        }
    } while ($retry -eq "oui")
}

# fonction pour ajouter un concours et ses récompenses associées
# fonction simple donc pas beaucoup de commentaires
function Add-Concours {
    $csv = Import-Csv $concoursFile
    $nom = Read-Host "Nom du concours"
    # vérifie si le concours existe déjà en comparant le nom avec les noms existants dans le CSV
    if ($csv.NomConcours -contains $nom) {
        Write-Host "Concours existant." -ForegroundColor Yellow
        Write-Log ERROR "Concours '$nom' existe déjà."
        Write-Host "Appuyez sur ENTREE pour continuer..." -ForegroundColor Red
        Read-Host
        return
    }
    $concours = [PSCustomObject]@{
        NomConcours  = $nom
        DateCreation = Get-Date -Format 'yyyy-MM-dd'
    }
    $csv += $concours
    $csv | Export-Csv -NoTypeInformation -Encoding UTF8 $concoursFile
    Save-File $concoursFile
    Write-Log INFO "Concours '$nom' créé."

    $recomp = Import-Csv $recompensesFile
    do {
        $titre = Read-Host "Titre de la récompense"
        $seuil = Read-Host "Seuil de points"
        $recomp += [PSCustomObject]@{
            NomConcours     = $nom
            TitreRecompense = $titre
            Seuil           = $seuil
        }
        $plus = Read-Host "Ajouter une autre récompense ? (oui/non)"
    } while ($plus -eq "oui")
    $recomp | Export-Csv -NoTypeInformation -Encoding UTF8 $recompensesFile
    Save-File $recompensesFile
    Write-Log INFO "Récompenses ajoutées pour '$nom'."
}

# fonction pour ajouter un résultat de concours pour un tireur
function Add-Résultat {
    $concours = Import-Csv $concoursFile
    # vérifie si des concours existent
    if ($concours.Count -eq 0) {
        Write-Host "Aucun concours." -ForegroundColor Red
        Write-Log ERROR "Ajout résultat impossible : aucun concours."
        Write-Host "Appuyez sur ENTREE pour continuer..." -ForegroundColor Red
        Read-Host
        return
    }
    Write-Host "`n--- Concours disponibles ---" -ForegroundColor Cyan
    $concours | ForEach-Object { Write-Host "- $($_.NomConcours)" }

    $tireurs = Import-Csv $tireursFile
    # vérifie si des tireurs existent
    if ($tireurs.Count -eq 0) {
        Write-Host "Aucun tireur disponible." -ForegroundColor Red
        Write-Log ERROR "Ajout résultat impossible : aucun tireur."
        Write-Host "Appuyez sur ENTREE pour continuer..." -ForegroundColor Red
        Read-Host
        return
    }
    Write-Host "`n--- Tireurs disponibles ---" -ForegroundColor Cyan
    $tireurs | ForEach-Object { Write-Host "- $($_.NumeroFusil) : $($_.Prenom) $($_.Nom)" }
    write-Host ""
    

    $nom = Read-Host "Nom du concours"
    # vérifie si le concours existe en comparant le nom avec les noms existants dans le CSV
    # -not permet de vérifier si le nom n'est pas dans la liste des concours
    if (-not ($concours.NomConcours -contains $nom)) {
        Write-Host "Introuvable." -ForegroundColor Red
        Write-Log ERROR "Concours '$nom' introuvable."
        Write-Host "Appuyez sur ENTREE pour continuer..." -ForegroundColor Red
        Read-Host
        return
    }

    $numero = Read-Host "Numéro de fusil"
    # vérifie si le numéro de fusil existe en comparant le numéro avec les numéros existants dans le CSV
    # -not permet de vérifier si le numéro n'est pas dans la liste des tireurs
    if (-not ($tireurs.NumeroFusil -contains $numero)) {
        Write-Host "Tireur introuvable." -ForegroundColor Red
        Write-Log ERROR "Numéro fusil '$numero' introuvable."
        Write-Host "Appuyez sur ENTREE pour continuer..." -ForegroundColor Red
        Read-Host
        return
    }

    $score = [int](Read-Host "Score obtenu")
    
    $recompenses = Import-Csv $recompensesFile | Where-Object { $_.NomConcours -eq $nom } # $_ représente l'objet courant dans la boucle. Ce qui veut dire que $_.NomConcours accède à la propriété NomConcours de l'objet courant
    $gagnees = $recompenses | Where-Object { $score -ge [int]$_.Seuil } | Select-Object -Expand TitreRecompense
    $recompense = ($gagnees | Sort-Object) -join " + "

    $res = Import-Csv $resultatsFile
    $res += [PSCustomObject]@{
        NumeroFusil = $numero
        NomConcours = $nom
        Score       = $score
        Recompense  = $recompense
        Date        = Get-Date -Format 'yyyy-MM-dd'
    }
    $res | Export-Csv -NoTypeInformation -Encoding UTF8 $resultatsFile
    Save-File $resultatsFile
    Write-Log INFO "Résultat $numero - $nom - $score points enregistré."
}


function Show-Logs {
    Write-Host "--- Logs INFO ---" -ForegroundColor Cyan
    Get-Content "$localTempPath\log_info.txt" | ForEach-Object { Write-Host $_ }
    Write-Host "\n--- Logs ERREUR ---" -ForegroundColor Red
    Get-Content "$localTempPath\log_error.txt" | ForEach-Object { Write-Host $_ }
    Write-Host "Appuyez sur ENTREE pour continuer..." -ForegroundColor Red
    Read-Host


}

function Show-AllTireurs {
    $csv = Import-Csv $tireursFile
    Write-Host "\n=== Liste complète des tireurs ==="
    foreach ($t in $csv) {
        Write-Host "--------------------------"
        Write-Host "Fusil   : $($t.NumeroFusil)"
        Write-Host "Nom     : $($t.Prenom) $($t.Nom)"
        Write-Host "Naissance : $($t.DateNaissance)"
        Write-Host "Téléphone : $($t.Telephone)"
        Write-Host "Email     : $($t.Email)"
        Write-Host "Adresse   : $($t.Adresse) $($t.NPA) $($t.Ville)"
        Write-Host "Inscrit le: $($t.DateInscription)"
        Write-Host "Appuyez sur ENTREE pour continuer..." -ForegroundColor Red
        Read-Host

    }
}

function Show-Tireur {
    $csv = Import-Csv $tireursFile

    if ($csv.Count -eq 0) {
        Write-Host "Aucun tireur disponible." -ForegroundColor Red
        Write-Host "Appuyez sur ENTREE pour continuer..." -ForegroundColor Red
        Read-Host

        return
    }
    Write-Host "`n--- Tireurs disponibles ---" -ForegroundColor Cyan
    $csv | ForEach-Object { Write-Host "- $($_.NumeroFusil) : $($_.Prenom) $($_.Nom)" }

    $numero = Read-Host "Numéro de fusil du tireur à afficher"
    $tireur = $csv | Where-Object { $_.NumeroFusil -eq $numero }

    if (-not $tireur) {
        Write-Host "Tireur introuvable." -ForegroundColor Red
        Write-Host "Appuyez sur ENTREE pour continuer..." -ForegroundColor Red
        Read-Host

        return
    }

    Write-Host "`n=== Détails du tireur ==="
    Write-Host "Fusil     : $($tireur.NumeroFusil)"
    Write-Host "Nom       : $($tireur.Prenom) $($tireur.Nom)"
    Write-Host "Naissance : $($tireur.DateNaissance)"
    Write-Host "AVS       : $($tireur.NumeroAVS)"
    Write-Host "Téléphone : $($tireur.Telephone)"
    Write-Host "Email     : $($tireur.Email)"
    Write-Host "Adresse   : $($tireur.Adresse), $($tireur.NPA) $($tireur.Ville)"
    Write-Host "Inscrit le: $($tireur.DateInscription)"
    write-Host "--------------------------"
    Write-Host ("La fiche du tireur est aussi disponible à l'adresse suivante : https://cesarcorpataux.emf-informatique.ch/script-122/tireur_" + $tireur.NumeroFusil + ".html")
    Write-Host "Appuyez sur ENTREE pour continuer..." -ForegroundColor Red
    Read-Host

    $htmlContent = @"
<!DOCTYPE html>
<html lang='fr'>
<head><meta charset='UTF-8'><title>$($tireur.Prenom) $($tireur.Nom)</title></head>
<body>
    <h1>$($tireur.Prenom) $($tireur.Nom)</h1>
    <ul>
        <li><strong>Fusil:</strong> $($tireur.NumeroFusil)</li>
        <li><strong>Naissance:</strong> $($tireur.DateNaissance)</li>
        <li><strong>AVS:</strong> $($tireur.NumeroAVS)</li>
        <li><strong>Téléphone:</strong> $($tireur.Telephone)</li>
        <li><strong>Email:</strong> $($tireur.Email)</li>
        <li><strong>Adresse:</strong> $($tireur.Adresse), $($tireur.NPA) $($tireur.Ville)</li>
        <li><strong>Date d'inscription:</strong> $($tireur.DateInscription)</li>
    </ul>
    <a href='index.html'>← Retour à l'index</a>
</body>
</html>
"@

    $filename = "tireur_$numero.html"
    $filepath = Join-Path $localTempPath $filename
    $htmlContent | Set-Content -Encoding UTF8 $filepath
    Save-File $filepath
    Update-Index
}

function Update-Index {
    $csv = Import-Csv $tireursFile
    $links = $csv | ForEach-Object {
        "<p><a href='tireur_$($_.NumeroFusil).html'><button>$($_.Prenom) $($_.Nom)</button></a></p>"
    }

    $html = @"
<!DOCTYPE html>
<html lang='fr'>
<head><meta charset='UTF-8'><title>Liste des tireurs</title></head>
<body>
    <h1>Index des tireurs</h1>
    $($links -join "`n")
</body>
</html>
"@

    $indexPath = Join-Path $localTempPath "index.html"
    $html | Set-Content -Encoding UTF8 $indexPath
    Save-File $indexPath
}


function Menu {
    do {
        Clear-Host
        Write-Host "                |======================|"
        Write-Host "                |    MENU PRINCIPAL    |"
        Write-Host "                |======================|"
        write-Host ""
        write-Host "   |====================================================|"
        Write-Host "1. |Ajouter un tireur                                   |"
        write-Host "   |----------------------------------------------------|"
        Write-Host "2. |Créer un concours                                   |"
        write-Host "   |----------------------------------------------------|"
        Write-Host "3. |Entrer un résultat de concours                      |"
        write-Host "   |----------------------------------------------------|"
        Write-Host "4. |Afficher un tireur (et générer sa page web)         |"
        write-Host "   |----------------------------------------------------|"
        Write-Host "5. |Afficher tous les tireurs                           |"
        Write-Host "   |====================================================|"
        Write-Host "6. |Voir les logs                                       |"
        write-Host "   |----------------------------------------------------|"
        Write-Host "7  |Actualiser les fichiers                             |"
        write-Host "   |----------------------------------------------------|"
        Write-Host "8. |Quitter                                             |"
        write-Host "   |====================================================|"
        write-Host ""
        $choix = Read-Host "Choix (1-8)"
        switch ($choix) {
            "1" { Add-Tireur }
            "2" { Add-Concours }
            "3" { Add-Résultat }
            "4" { Show-Tireur }
            "5" { Show-AllTireurs }
            "6" { Show-Logs }
            "7" { Get-All }
            "8" {
                Write-Host "Fermeture du programme." -ForegroundColor Green
                Write-Host "Merci d'avoir utilisé le programme $UserName." -ForegroundColor Cyan
                Start-Sleep -Seconds 2
                Clear-Host
                exit 
            }

            default {
                Write-Host "Choix invalide." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    } while ($true)
}

Get-All
Menu
