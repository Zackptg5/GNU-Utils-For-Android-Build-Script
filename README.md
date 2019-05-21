## GNU Utils for Android Build Script ##

This will build any of the following static GNU binaries:<br/>
bash, bc (also includes dc), coreutils (includes advanced cp/mv - progress bar functionality), cpio, diffutils (includes cmp, diff, diff3, sdiff), ed, findutils (includes find, bigram, code, frcode, locate, xargs), gawk (GNU awk), grep (also includes egrep and fgrep), gzip (also includes gunzip and gzexe), ncurses (includes capconvert, clear, infocmp, tabs, tic, toe, tput, tset), patch, sed, tar

## Build instructions

```
sudo apt install build-essential gcc-multilib libgnutls28-dev lzip # For debian/ubuntu based distributions - install equivalent dev tools and dependencies for yours
./build.bash BIN=<BIN> ARCH=<ARCH>
```

## Notes

- The bash patches are for bash 4.4-23 and 5.0.x stable. If you're compiling any other version of bash, make sure the patch files are targeting the correct lines
- The advcpmv patch is for coreutils 8.31. If you're compiling any other version, you may need to modify it to target the correct lines
- If building fails, you likely need to add/remove/modify patches. Just place the patches in the patches folder and the script will apply them

## Credits

* [GNU](https://www.gnu.org/software/)

### Credits for Bash and Patches

* [Alexander Gromnitsky](https://github.com/gromnitsky/bash-on-android)
* [Termux](https://github.com/termux/termux-packages/tree/master/packages/bash)
* [ATechnoHazard and koro666](https://github.com/ATechnoHazard/bash_patches)
* [BlissRoms](https://github.com/BlissRoms/platform_external_bash)
  
## License

  MIT
