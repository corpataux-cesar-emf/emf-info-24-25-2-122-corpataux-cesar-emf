# =================================================================================
# Auteur      : Corpataux César
# Date        : 2025-06-04
# Version     : 4.4
# Description : Gestion des tireurs, concours, résultats, génération HTML et upload FTP sécurisé
# Paramètres  : UTF-8, persistance fichiers
# =================================================================================

# Configuration de l'encodage en UTF-8 pour assurer la compatibilité des caractères spéciaux
chcp 65001 > $null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# === Chemins des dossiers et fichiers ===
$basePath = "scriptFiles"
if (-not (Test-Path $basePath)) {
    New-Item -Path $basePath -ItemType Directory | Out-Null  # Création du dossier si absent
}

$tireursFile     = Join-Path $basePath "tireurs.csv"
$concoursFile    = Join-Path $basePath "concours.csv"
$recompensesFile = Join-Path $basePath "recompenses.csv"
$resultatsFile   = Join-Path $basePath "resultats.csv"
$logFile         = Join-Path $basePath "logs.log"
$htmlPath        = "Z:\www"

if (-not (Test-Path $htmlPath)) {
    New-Item -Path $htmlPath -ItemType Directory | Out-Null  # Création du dossier HTML
}

# === Initialisation des fichiers CSV ===
function Initialize-CsvFile {
    param($path, $header)
    if (-not (Test-Path $path)) {
        $header | Out-File -FilePath $path -Encoding utf8
        Add-Content $logFile "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - INFO - Création de $path"
    }
}

Initialize-CsvFile $tireursFile     "NumeroFusil,Nom,Prenom,DateNaissance,NumeroAVS,Telephone,Email,Adresse,NPA,Ville,DateInscription"
Initialize-CsvFile $concoursFile    "NomConcours,DateCreation"
Initialize-CsvFile $recompensesFile "NomConcours,TitreRecompense,Seuil"
Initialize-CsvFile $resultatsFile   "NumeroFusil,NomConcours,Score,Recompense,Date"

if (-not (Test-Path $logFile)) {
    New-Item $logFile -ItemType File -Encoding utf8 | Out-Null
}

# === Fonction d'envoi FTP sécurisé avec mot de passe chiffré dans un fichier ===
function Publish-FileToFTP {
    param (
        [string]$localFilePath,
        [string]$remoteFileName
    )

    $ftpServer = "ftp://cesarcorpataux.emf-informatique.ch"
    $ftpUsername = "cesarcorpataux"
    $ftpPasswordSecure = Get-Content "ftp_password.txt" | ConvertTo-SecureString
    $ftpCredential = New-Object System.Management.Automation.PSCredential($ftpUsername, $ftpPasswordSecure)

    $remoteUrl = $ftpServer + $remoteFileName
    $webclient = New-Object System.Net.WebClient
    $webclient.Credentials = $ftpCredential

    try {
        $webclient.UploadFile($remoteUrl, "STOR", $localFilePath)
        Write-Host "✅ Fichier FTP envoyé : $remoteFileName" -ForegroundColor Green
        Add-Content $logFile "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - INFO - FTP upload : $remoteFileName"
    }
    catch {
        Write-Host "❌ Échec FTP : $_" -ForegroundColor Red
        Add-Content $logFile "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR - FTP upload : $_"
    }
}

# === Ajout d’un tireur avec vérification de doublon ===
function Add-Tireur {
    do {
        $numeroFusil = Read-Host "Numéro de fusil"
        if (Select-String -Path $tireursFile -Pattern "^$numeroFusil,") {
            Write-Host "Ce numéro de fusil existe déjà." -ForegroundColor Yellow
            $retry = Read-Host "Essayer un autre numéro ? (oui/non)"
        }
        else {
            $retry = "non"
            $nom    = Read-Host "Nom"
            $prenom = Read-Host "Prénom"
            $dob    = Read-Host "Date de naissance (YYYY-MM-DD)"
            $avs    = Read-Host "Numéro AVS"
            $tel    = Read-Host "Téléphone"
            $mail   = Read-Host "Email"
            $adresse= Read-Host "Adresse"
            $npa    = Read-Host "NPA"
            $ville  = Read-Host "Ville"
            $dateInscription = Get-Date -Format 'yyyy-MM-dd'

            "$numeroFusil,$nom,$prenom,$dob,$avs,$tel,$mail,$adresse,$npa,$ville,$dateInscription" | Add-Content $tireursFile
            Add-Content $logFile "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - INFO - Tireur $nom $prenom ajouté."
        }
    } while ($retry -eq "oui")
}

# === Création d’un concours avec ses récompenses ===
function Add-Concours {
    $nomConcours = Read-Host "Nom du concours"
    if (Select-String -Path $concoursFile -Pattern "^$nomConcours,") {
        Write-Host "Ce concours existe déjà." -ForegroundColor Yellow
        return
    }

    $date = Get-Date -Format 'yyyy-MM-dd'
    "$nomConcours,$date" | Add-Content $concoursFile
    Add-Content $logFile "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - INFO - Concours $nomConcours créé."

    do {
        $titre = Read-Host "Titre de la récompense"
        $seuil = Read-Host "Seuil de points"
        "$nomConcours,$titre,$seuil" | Add-Content $recompensesFile
        $autre = Read-Host "Ajouter une autre récompense ? (oui/non)"
    } while ($autre -eq "oui")
}

# === Ajout d’un résultat et attribution automatique de récompenses ===
function Add-Résultat {
    $concours = Get-Content $concoursFile | Select-Object -Skip 1
    if ($concours.Count -eq 0) {
        Write-Host "Aucun concours disponible." -ForegroundColor Red
        return
    }

    Write-Host "`nConcours disponibles :"
    $concours | ForEach-Object { ($_ -split ",")[0] }

    $nomConcours = Read-Host "Nom du concours"
    if (-not ($concours -match "^$nomConcours,")) {
        Write-Host "Concours introuvable." -ForegroundColor Red
        return
    }

    Write-Host "`n--- Liste des tireurs ---"
    $tireurs = Import-Csv $tireursFile
    foreach ($t in $tireurs) {
        Write-Host "$($t.NumeroFusil) : $($t.Nom) $($t.Prenom)"
    }

    do {
        $numeroFusil = Read-Host "`nNuméro de fusil du tireur"
        $ligne = Select-String -Path $tireursFile -Pattern "^$numeroFusil,"
        if (-not $ligne) {
            Write-Host "Tireur introuvable." -ForegroundColor Red
            $creer = Read-Host "Souhaitez-vous créer ce tireur ? (oui/non)"
            if ($creer -eq "oui") {
                Add-Tireur
            }
        }
    } while (-not (Select-String -Path $tireursFile -Pattern "^$numeroFusil,"))

    $score = [int](Read-Host "Score obtenu")
    $date = Get-Date -Format 'yyyy-MM-dd'

    $recompenses = Import-Csv $recompensesFile | Where-Object { $_.NomConcours -eq $nomConcours }
    $gagnees = $recompenses | Where-Object { $score -ge [int]$_.Seuil } | Select-Object -ExpandProperty TitreRecompense
    $recompense = ($gagnees | Sort-Object -Unique | Sort-Object) -join " + "

    "$numeroFusil,$nomConcours,$score,$recompense,$date" | Add-Content $resultatsFile
    Add-Content $logFile "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - INFO - Résultat enregistré : $numeroFusil, $nomConcours, $score, $recompense"
}

# === Affichage détaillé d’un tireur et génération page HTML ===
function Show-Tireur {
    Write-Host "`n--- Liste des tireurs enregistrés ---"
    $tireurs = Import-Csv $tireursFile
    foreach ($t in $tireurs) {
        Write-Host "$($t.NumeroFusil) : $($t.Nom) $($t.Prenom)"
    }

    $numeroFusil = Read-Host "`nEntrez le numéro de fusil"
    $ligne = Select-String -Path $tireursFile -Pattern "^$numeroFusil,"
    if (-not $ligne) {
        Write-Host "Tireur non trouvé." -ForegroundColor Red
        return
    }

    $infos = $ligne.Line -split ","
    $resultats = Import-Csv $resultatsFile | Where-Object { $_.NumeroFusil -eq $numeroFusil }

    Write-Host "`n--- Informations du tireur ---"
    Write-Host "Nom       : $($infos[1])"
    Write-Host "Prénom    : $($infos[2])"
    Write-Host "Date Naiss: $($infos[3])"
    Write-Host "AVS       : $($infos[4])"
    Write-Host "Téléphone : $($infos[5])"
    Write-Host "Email     : $($infos[6])"
    Write-Host "Adresse   : $($infos[7]) $($infos[8]) $($infos[9])"
    Write-Host "Inscrit le: $($infos[10])"

    Write-Host "`n--- Résultats ---"
    foreach ($r in $resultats) {
        $recomp = if ($r.Recompense) { $r.Recompense } else { "Aucune" }
        Write-Host "$($r.NomConcours) : $($r.Score) points, Récompense : $recomp"
    }

    # Génération HTML
    $html = @"
<html><head><meta charset="UTF-8"><title>Tireur - $($infos[1]) $($infos[2])</title></head><body>
<h2>Fiche du tireur</h2>
<p><strong>Nom :</strong> $($infos[1])</p>
<p><strong>Prénom :</strong> $($infos[2])</p>
<p><strong>Date de naissance :</strong> $($infos[3])</p>
<p><strong>Email :</strong> $($infos[6])</p>
<p><strong>Adresse :</strong> $($infos[7]) $($infos[8]) $($infos[9])</p>
<h3>Résultats</h3>
<ul>
"@
    foreach ($r in $resultats) {
        $html += "<li>$($r.NomConcours) : $($r.Score) points - Récompense : $($r.Recompense)</li>"
    }
    $html += "</ul></body></html>"

    $fichierNom = "tireur_{0}.html" -f $infos[0]
    $pagePath = Join-Path $htmlPath $fichierNom
    $html | Out-File -Encoding UTF8 -FilePath $pagePath

    Upload-FileToFTP -localFilePath $pagePath -remoteFileName $fichierNom
    Add-AccueilPage
}

# === Page d’accueil HTML (index) ===
function Add-AccueilPage {
    $tireurs = Import-Csv $tireursFile
    $html = @"
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>Accueil - Liste des tireurs</title>
    <style>
        body { font-family: Arial; margin: 30px; background-color: #f4f4f4; }
        h1 { color: #333; }
        .btn {
            display: inline-block;
            padding: 10px 20px;
            margin: 8px;
            background-color: #007BFF;
            color: white;
            text-decoration: none;
            border-radius: 5px;
        }
        .btn:hover { background-color: #0056b3; }
    </style>
</head>
<body>
    <h1>Liste des tireurs</h1>
"@

    foreach ($t in $tireurs) {
        $fichierNom = "tireur_$($t.NumeroFusil).html"
        $pagePath = Join-Path $htmlPath $fichierNom
        if (Test-Path $pagePath) {
            $html += "<a class='btn' href='$fichierNom' target='_blank'>$($t.Prenom) $($t.Nom)</a>`n"
        }
    }

    $html += "</body></html>"
    $accueilPath = Join-Path $htmlPath "index.html"
    $html | Out-File -Encoding UTF8 -FilePath $accueilPath

    Upload-FileToFTP -localFilePath $accueilPath -remoteFileName "index.html"
    Write-Host "`nPage d'accueil mise à jour et envoyée par FTP." -ForegroundColor Green
    Add-Content $logFile "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - INFO - Page d'accueil HTML générée et envoyée."
}

# === Affiche tous les tireurs et leurs résultats ===
function Show-AllTireurs {
    Clear-Host
    Write-Host "`n=== Liste complète des tireurs enregistrés ===`n"
    $tireurs = Import-Csv $tireursFile
    $resultats = Import-Csv $resultatsFile

    foreach ($t in $tireurs) {
        Write-Host "--------------------------------------------"
        Write-Host "Numéro fusil : $($t.NumeroFusil)"
        Write-Host "Nom          : $($t.Nom)"
        Write-Host "Prénom       : $($t.Prenom)"
        Write-Host "Date Naiss.  : $($t.DateNaissance)"
        Write-Host "Téléphone    : $($t.Telephone)"
        Write-Host "Email        : $($t.Email)"
        Write-Host "Adresse      : $($t.Adresse) $($t.NPA) $($t.Ville)"
        Write-Host "Inscription  : $($t.DateInscription)"

        $res = $resultats | Where-Object { $_.NumeroFusil -eq $t.NumeroFusil }
        if ($res.Count -gt 0) {
            Write-Host "Résultats    :"
            foreach ($r in $res) {
                $recomp = if ($r.Recompense) { $r.Recompense } else { "Aucune" }
                Write-Host "  - $($r.NomConcours) : $($r.Score) points, Récompense : $recomp"
            }
        } else {
            Write-Host "Résultats    : Aucun"
        }
        Write-Host ""
    }

    Write-Host "`nAppuyez sur Entrée pour revenir au menu principal..."
    [void][System.Console]::ReadLine()
}

# === MENU PRINCIPAL ===
do {
    Clear-Host
    Write-Host "=== MENU PRINCIPAL ==="
    Write-Host "1. Ajouter un tireur"
    Write-Host "2. Créer un concours"
    Write-Host "3. Entrer un résultat de concours"
    Write-Host "4. Afficher un tireur"
    Write-Host "5. Afficher tous les tireurs"
    Write-Host "6. Quitter"
    $choix = (Read-Host "Choix (1-6)").Trim()

    switch ($choix) {
        "1" { Add-Tireur }
        "2" { Add-Concours }
        "3" { Add-Résultat }
        "4" { Show-Tireur }
        "5" { Show-AllTireurs }
        "6" {
            Write-Host "`nProgramme terminé." -ForegroundColor Red
            exit
        }
        default {
            Write-Host "Choix invalide. Veuillez entrer un chiffre entre 1 et 6." -ForegroundColor Yellow
        }
    }

    Write-Host "`nAppuyez sur Entrée pour continuer..."
    [void][System.Console]::ReadLine()
} while ($true)
