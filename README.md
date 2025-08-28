# Portage-based script for creating AppImages

This project aims to simplify and automate the process of building AppImages using Gentoo's Portage system. It provides scripts, guides, and resources to help users create portable application bundles, making software distribution and deployment easier on Gentoo Linux.

## Purpose

The purpose of this repository is to:
- Automate the creation of AppImages from Gentoo packages.
- Offer customizable scripts for various application needs.
  For example building AppImages for different architectures and/or different CFLAGS much easier, in a automated way.
- Document best practices for configuring and maintaining Gentoo systems.
- Support both newcomers and advanced users in streamlining their Gentoo & packaging experience.

## Example: Creating an AppImage

Follow these steps to build an AppImage for a package:

```sh
git clone https://github.com/StefanCristian/emerge-appimage.git
cd emerge-appimage

# Run the AppImage creation script for a specific package
./mk-appimage.sh <package-name> short-name uppercharacter-name
```

Replace `<package-name>` with the desired Gentoo package (e.g., `firefox`).

Current status:
- Packages are emerged with --nodeps, so you need to have the package dependencies satisfied before.
- Packages with data (like usr/share) directories are harder to treat, so there will be caveats in building games, for example.
- Limitation on building non-generic -march, it's recommended to have a generic -march chroot to build a -march=native app, not vice-versa.
  It's due to the fact that the script includes already-built libraries from the system, so if you build a generic say march=x86-64,
  and if you have your whole system as -march=native, the end result would be a march=x86-64, but with march=native libraries bundled,
  and that will not be portable.
  Hence, I recommend using this in a stage3 generic -march chroot, if you have your system as -march=native.
  Otherwise, feel free to name your AppImages as your exact CPU architecture and deliver them, they will work on the same CPU.