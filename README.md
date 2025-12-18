# PowerShell Report Builder
🏗️ **Générateur de rapports HTML interactif basé sur PSWriteHTML**

PowerShell Report Builder est une application WPF permettant de créer et modifier des rapports HTML de manière interactive, sans connaissances préalables en HTML, CSS ou JavaScript.

## ✨ Fonctionnalités

### 🎨 Interface Visuelle
- Designer visuel pour créer des rapports
- Arborescence de la structure du rapport
- Prévisualisation en temps réel
- Génération automatique du code PowerShell

### 📦 Éléments de Rapport
- **Onglets** (Tab) - Organisation par onglets
- **Sections** - Regroupement de contenu avec en-têtes
- **Panneaux** - Mise en page flexible
- **Tableaux** - Affichage de données avec recherche, tri et pagination
- **Graphiques** - Barres, camemberts, lignes, donuts
- **Texte** - Contenu textuel formaté

### 🗃️ Sources de Données
- **CSV** - Fichiers CSV avec délimiteur configurable
- **JSON** - Fichiers JSON
- **SQL Server** - Requêtes SQL avec authentification Windows ou SQL
- **Microsoft Graph** - API Microsoft 365 (utilisateurs, groupes, etc.)
- **Manuel** - Saisie directe de données

## 📋 Prérequis

- Windows PowerShell 5.1 ou supérieur
- Droits administrateur (pour l'installation des modules)
- .NET Framework 4.7.2+

## 🚀 Installation

1. Clonez le repository :
```powershell
git clone https://github.com/mchave3/PSReportBuilder.git
cd PSReportBuilder
```

2. Lancez l'application :
```powershell
.\PSReportBuilder.ps1
```

Les modules requis (PSWriteHTML, Microsoft.Graph.Authentication) seront installés automatiquement si nécessaire.

## 📁 Structure du Projet

```
PSReportBuilder/
├── PSReportBuilder.ps1      # Script principal
├── Modules/
│   ├── ReportElements.psm1  # Gestion des éléments de rapport
│   ├── DataSources.psm1     # Gestion des sources de données
│   └── ReportGenerator.psm1 # Génération des rapports HTML
├── XAML/
│   ├── MainWindow.xaml      # Fenêtre principale
│   ├── DataSourceDialog.xaml # Dialog source de données
│   └── ElementPropertiesDialog.xaml # Dialog propriétés
└── Logs/                    # Fichiers de log
```

## 🎯 Utilisation

### Créer un nouveau rapport

1. Lancez l'application
2. Ajoutez des éléments depuis la boîte à outils (panneau gauche)
3. Configurez les propriétés de chaque élément (panneau droit)
4. Ajoutez des sources de données si nécessaire
5. Prévisualisez le rapport avec le bouton ▶️
6. Exportez en HTML ou sauvegardez le projet

### Exemple de structure de rapport

```
📑 Onglet Dashboard
  └── 📦 Section Résumé
      ├── 🗂️ Panneau
      │   └── 📊 Tableau Utilisateurs
      └── 🗂️ Panneau
          └── 📈 Graphique Stats
📑 Onglet Détails
  └── 📦 Section Données
      └── 📊 Tableau Complet
```

## 🔧 Technologies

- **[PSWriteHTML](https://github.com/EvotecIT/PSWriteHTML)** - Module PowerShell pour la génération HTML
- **WPF (XAML)** - Interface utilisateur Windows
- **Microsoft Graph** - Intégration Microsoft 365

## 📝 Licence

MIT License - Voir [LICENSE](LICENSE)

## 🤝 Contribution

Les contributions sont les bienvenues ! N'hésitez pas à ouvrir une issue ou une pull request.