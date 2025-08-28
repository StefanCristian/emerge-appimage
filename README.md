# Portage-based script for creating AppImages

This project aims to simplify and automate the process of building AppImages using Gentoo's Portage system. It provides scripts, guides, and resources to help users create portable application bundles, making software distribution and deployment easier on Gentoo Linux.

## Purpose

The purpose of this repository is to:
- Automate the creation of AppImages from Gentoo packages.
- Offer customizable scripts for various application needs.
- Document best practices for configuring and maintaining Gentoo systems.
- Support both newcomers and advanced users in streamlining their Gentoo & packaging experience.

## Example: Creating an AppImage

Follow these steps to build an AppImage for a package:

```sh
# Clone the repository
git clone https://github.com/StefanCristian/emerge-appimage.git
cd emerge-appimage

# Run the AppImage creation script for a specific package
./mk-appimage.sh <package-name> short-name uppercharacter-name
```

Replace `<package-name>` with the desired Gentoo package (e.g., `firefox`).
