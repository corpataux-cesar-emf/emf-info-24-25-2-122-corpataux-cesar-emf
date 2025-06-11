# =================================================================================
# Auteur      : Corpataux César
# Date        : 2025-06-03
# Version     : 4.2
# Description : Gestion tireurs, concours, résultats, HTML et mail
# Paramètres  : UTF-8, persistance fichiers
# =================================================================================

#Internet
chcp 65001 > $null #on change la page de code pour UTF-8. chcp veut dire "change code page" et 65001 est le code pour UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8 #on configure l'encodage de la console pour qu'il utilise UTF-8

# === Dossier de stockage ===
$basePath = $PSScriptRoot  # Emplacement des fichiers de données
if (-not (Test-Path $basePath)) {   # Si le dossier scriptFiles n'existe pas
    New-Item -Path $basePath -ItemType Directory | Out-Null  # On le crée
}

# === Chemins des fichiers CSV utilisés pour enregistrer les données ===
$tireursFile     = Join-Path $basePath "tireurs.csv"
$concoursFile    = Join-Path $basePath "concours.csv"
$recompensesFile = Join-Path $basePath "recompenses.csv"
$resultatsFile   = Join-Path $basePath "resultats.csv"
$logFile         = Join-Path $basePath "logs.log"
$pageWebFile     = Join-Path $basePath "tireur.html"   # ⬅ HTML généré dans le dossier du script
#Join-Path colle $basePath/PSScriptRoot et le nom du fichier pour créer un chemin complet

# === Fonction pour initialiser un fichier avec une ligne d'en-tête si nécessaire ===
function Initialize-CsvFile {
    param($path, $header) # Paramètres : chemin du fichier et en-tête à ajouter
    if (-not (Test-Path $path)) {  # Si le fichier n'existe pas
        $header | Out-File -FilePath $path -Encoding utf8 # On le crée avec l'en-tête associé
        Add-Content $logFile "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - INFO - Création de $path"
    }
}

# Initialisation des fichiers CSV avec leur en-tête
# on donnes les entetes des fichiers CSV entre guillemets
# les variables (comme $tireursFile ou $concoursFile) sont des chemins vers les fichiers)
Initialize-CsvFile $tireursFile     "NumeroFusil,Nom,Prenom,DateNaissance,NumeroAVS,Telephone,Email,Adresse,NPA,Ville,DateInscription"
Initialize-CsvFile $concoursFile    "NomConcours,DateCreation"
Initialize-CsvFile $recompensesFile "NomConcours,TitreRecompense,Seuil"
Initialize-CsvFile $resultatsFile   "NumeroFusil,NomConcours,Score,Recompense,Date"
if (-not (Test-Path $logFile)) {
    New-Item $logFile -ItemType File -Encoding utf8 | Out-Null  # Création du fichier log s’il n’existe pas
}

# === Fonction pour ajouter un tireur ===
function Add-Tireur {
    do {
        $numeroFusil = Read-Host "Numéro de fusil"  # ça vas être l'identifiant du tireur car le numéro atribué à chaque fusil est unique
        # Vérifie que le numéro de fusil n'existe pas déjà
        if (Select-String -Path $tireursFile -Pattern "^$numeroFusil,") {
            # select-string permet de chercher une ligne dans un fichier,
            #-path permet de spécifier le fichier,
            #-pattern permet de spécifier le motif à chercher
            Write-Host "Ce numéro de fusil existe déjà." -ForegroundColor Yellow
            $retry = Read-Host "Souhaitez-vous essayer avec un autre numéro ? (oui/non)"
        } else {
            $retry = "non"
            # Saisie des autres informations personnelles
            $nom     = Read-Host "Nom"
            $prenom  = Read-Host "Prénom"
            $dob     = Read-Host "Date de naissance (YYYY-MM-DD)"
            $avs     = Read-Host "Numéro AVS"
            $tel     = Read-Host "Numéro de téléphone"
            $mail    = Read-Host "Adresse mail"
            $adresse = Read-Host "Adresse"
            $npa     = Read-Host "NPA"
            $ville   = Read-Host "Ville"
            $dateInscription = Get-Date -Format 'yyyy-MM-dd'  # Date du jour 

            # Ajout dans le fichier CSV
            "$numeroFusil,$nom,$prenom,$dob,$avs,$tel,$mail,$adresse,$npa,$ville,$dateInscription" | Add-Content $tireursFile
            Add-Content $logFile "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - INFO - Tireur $nom $prenom ajouté."
            #add-content permet d'ajouter du contenu à un fichier
        }
    } while ($retry -eq "oui")
}

# === Fonction pour ajouter un concours et ses récompenses ===
function Add-Concours {
    $nomConcours = Read-Host "Nom du concours"
    if (Select-String -Path $concoursFile -Pattern "^$nomConcours,") {
        Write-Host "Ce concours existe déjà !" -ForegroundColor Yellow
        return
    }
    $date = Get-Date -Format 'yyyy-MM-dd'
    "$nomConcours,$date" | Add-Content $concoursFile
    Add-Content $logFile "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - INFO - Concours $nomConcours créé."

    # Ajout des récompenses liées à ce concours
    do {
        $titre = Read-Host "Titre de la récompense"
        $seuil = Read-Host "Seuil de points"
        "$nomConcours,$titre,$seuil" | Add-Content $recompensesFile
        $autre = Read-Host "Ajouter une autre récompense ? (oui/non)"
    } while ($autre -eq "oui")
}

# === Fonction pour enregistrer un résultat de concours pour un tireur ===
# === Fonction pour enregistrer un résultat de concours pour un tireur ===
function# === Fonction corrigée pour enregistrer un résultat de concours pour un tireur ===
function Add-Résultat {
    # Récupération des concours existants
    $listeConcours = Import-Csv $concoursFile
    if ($listeConcours.Count -eq 0) {
        Write-Host "Aucun concours existant !" -ForegroundColor Red
        return
    }

    # Affiche les concours disponibles
    Write-Host "`nConcours disponibles :"
    $listeConcours | ForEach-Object { Write-Host "- $($_.NomConcours)" }

    # Sélection du concours
    $nomConcours = Read-Host "Nom du concours"
    if (-not ($listeConcours | Where-Object { $_.NomConcours -eq $nomConcours })) {
        Write-Host "Concours invalide !" -ForegroundColor Red
        return
    }

    # Affiche la liste des tireurs avant de saisir un résultat
    Write-Host "`n--- Liste des tireurs ---"
    $tireurs = Import-Csv $tireursFile
    foreach ($t in $tireurs) {
        Write-Host "$($t.NumeroFusil) : $($t.Nom) $($t.Prenom)"
    }

    # Demande du numéro de fusil avec vérification
    do {
        $numeroFusil = Read-Host "`nNuméro de fusil du tireur"
        $ligne = Select-String -Path $tireursFile -Pattern "^$numeroFusil,"
        if (-not $ligne) {
            Write-Host "Tireur non trouvé." -ForegroundColor Red
            $creer = Read-Host "Voulez-vous créer ce tireur ? (oui/non)"
            if ($creer -eq "oui") {
                Add-Tireur
            }
        }
    } while (-not (Select-String -Path $tireursFile -Pattern "^$numeroFusil,"))

    # Saisie du score
    $score = [int](Read-Host "Score du tireur")
    $date = Get-Date -Format 'yyyy-MM-dd'

    # Calcul des récompenses obtenues
    $recompenses = Import-Csv $recompensesFile | Where-Object { $_.NomConcours -eq $nomConcours }
    $recompensesGagnees = $recompenses | Where-Object { $score -ge [int]$_.Seuil } | Select-Object -ExpandProperty TitreRecompense
    $recompense = ($recompensesGagnees | Sort-Object -Unique | Sort-Object) -join " + "

    # Enregistrement du résultat dans le CSV
    "$numeroFusil,$nomConcours,$score,$recompense,$date" | Add-Content $resultatsFile

    # Ajout au fichier log
    Add-Content $logFile "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - INFO - Résultat ajouté : $numeroFusil, $nomConcours, $score, $recompense"
    Write-Host "Résultat enregistré avec succès." -ForegroundColor Green
}



# === Fonction pour afficher un tireur précis ===
function Show-Tireur {
    Write-Host "`n--- Liste des tireurs enregistrés ---"
    $tireurs = Import-Csv $tireursFile
    foreach ($t in $tireurs) {
        Write-Host "$($t.NumeroFusil) : $($t.Nom) $($t.Prenom)"
    }

    $numeroFusil = Read-Host "`nEntrez le numéro de fusil du tireur à afficher"
    $ligne = Select-String -Path $tireursFile -Pattern "^$numeroFusil,"
    if (-not $ligne) {
        Write-Host "Tireur non trouvé." -ForegroundColor Red
        return
    }

    # Récupération des infos et résultats
    $infos = $ligne.Line -split ","
    $resultats = Import-Csv $resultatsFile | Where-Object { $_.NumeroFusil -eq $numeroFusil }

    # Affichage des informations
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

    # Génération de la page HTML
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

    $html | Out-File -Encoding UTF8 -FilePath $pageWebFile
    Add-Content $logFile "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - INFO - Page HTML générée pour $($infos[1]) $($infos[2])"
    Write-Host "`nPage HTML générée : $pageWebFile" -ForegroundColor Cyan
}

# === Fonction pour afficher tous les tireurs et leurs résultats ===
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

    Write-Host "Fin de la liste."
    Write-Host "`nAppuyez sur Entrée pour revenir au menu principal..."
    [void][System.Console]::ReadLine()
}

# === MENU PRINCIPAL : navigation entre les différentes actions ===
do {
    Clear-Host
    Write-Host "=== MENU PRINCIPAL ==="
    Write-Host "1. Ajouter un tireur"
    Write-Host "2. Créer un concours"
    Write-Host "3. Entrer un résultat de concours"
    Write-Host "4. Afficher un tireur"
    Write-Host "5. Afficher tous les tireurs"
    Write-Host "6. Quitter"
    $choix = (Read-Host "Veuillez choisir une option (1-6)").Trim()
    #.Trim() permet de supprimer les espaces avant et après la saisie

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
            Write-Host "Option invalide. Veuillez entrer un chiffre de 1 à 6." -ForegroundColor Yellow
        }
    }

    Write-Host "`nAppuyez sur Entrée pour continuer..."
    [void][System.Console]::ReadLine()

} while ($true)
