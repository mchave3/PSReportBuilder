# XAML - PowerShell Report Builder

Ce dossier contient les fichiers XAML pour l'interface utilisateur WPF de PowerShell Report Builder.

## Fichiers

### MainWindow.xaml
Fenêtre principale de l'application contenant :
- **Menu Bar** : Fichier, Édition, Données, Affichage, Aide
- **Toolbar** : Actions rapides (Nouveau, Ouvrir, Sauvegarder, Prévisualiser, Exporter)
- **Panneau gauche** :
  - Boîte à outils des éléments (Onglet, Section, Panneau, Tableau, Graphique, Texte)
  - Arborescence de la structure du rapport
- **Zone centrale** :
  - Onglet Designer : Zone de conception visuelle
  - Onglet Prévisualisation : Aperçu du rapport HTML
  - Onglet Code : Code PowerShell généré
- **Panneau droit** :
  - Propriétés de l'élément sélectionné
  - Liste des sources de données
- **Barre de statut** : Messages et compteur d'éléments

### DataSourceDialog.xaml
Dialogue pour ajouter/modifier une source de données supportant :
- **CSV** : Fichiers CSV avec délimiteur configurable
- **JSON** : Fichiers JSON
- **SQL Server** : Connexion SQL avec authentification Windows ou SQL
- **Microsoft Graph** : Endpoints Graph API avec presets courants
- **Manuel** : Saisie directe de données JSON

### ElementPropertiesDialog.xaml
Dialogue pour éditer les propriétés des éléments :
- **Tab** : Nom, icône FontAwesome
- **Section** : En-tête, repliable, invisible
- **Panel** : Couleur de fond
- **Table** : Source de données, options d'affichage
- **Chart** : Titre, type de graphique, source de données
- **Text** : Contenu, couleur, alignement, taille

## Style
Tous les dialogues utilisent un thème sombre cohérent avec :
- Fond principal : `#1E1E1E`
- Fond secondaire : `#2D2D2D`
- Accent : `#0078D4`
- Texte : `#CCCCCC` / Blanc