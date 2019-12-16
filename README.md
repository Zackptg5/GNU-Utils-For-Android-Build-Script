## GNU Utils for Android Build Script ##

This will build any of the following static GNU binaries:<br/>
bash, bc (also includes dc), coreutils (includes advanced cp/mv - progress bar functionality), cpio, diffutils (includes cmp, diff, diff3, sdiff), ed, findutils (includes find, locate, updatedb, xargs), gawk (GNU awk), grep (also includes egrep and fgrep) (has full perl regex support), gzip (also includes gunzip and gzexe), ncurses (includes capconvert, clear, infocmp, tabs, tic, toe, tput, tset), patch, sed, tar

## Build instructions

```
sudo apt install build-essential gcc-multilib libgnutls28-dev lzip # For debian/ubuntu based distributions - install equivalent dev tools and dependencies for yours
./build.bash --help # For more info on usage
```

## Note

If mirrors.kernel.org is down, replace all instances of that in build script with ftp.gnu.org

## Compatibility

The below table notes if the binary is compatible with android ndk, linaro, or gcc compilers. If static or dynamic is listed, then only that link method is working

|           | NDK?    | Linaro? | GCC?   |
| --------- |:-------:|:-------:|:------:|
| **bash**      | *Static*  | Yes     | Yes    |
| **bc**        | Yes     | Yes     | Yes    |
| **coreutils** | Yes     | *Static*  | *Static*  |
| **cpio**      | Yes     | Yes     | Yes    |
| **diffutils** | Yes     | Yes     | Yes    |
| **ed**        | Yes     | No      | No     |
| **findutils** | Yes     | *Dynamic* | *Dynamic* |
| **gawk**      | *Static*  | Yes     | Yes    |
| **grep**      | Yes       | Yes     | Yes    |
| **gzip**      | Yes     | Yes     | Yes    |
| **ncurses**   | Yes     | Yes     | Yes    |
| **patch**     | Yes     | Yes     | Yes    |
| **sed**       | Yes     | Yes     | Yes    |
| **tar**       | Yes     | Yes     | Yes    |

* NDK won't compile bash as static for arm64 architecture for reasons still unknown<br/>
* Pwcat and Grcat (part of gawk) seg fault when ndk is used, compile without it to use them

## Dynamic link Issue

If the binary wasn't compiled with NDK, it'll have library depenencies on non existent libraries. Some of these can be remedied with symlinks to it (for example: libc.so -> libc.so.6) but some can't because no version of it exists on android (like libreadline). In the case of libdl, even if symlink is made, it still doesn't work oddly.

## Credits

* [GNU](https://www.gnu.org/software/)

### Credits for Bash and Patches

* [Alexander Gromnitsky](https://github.com/gromnitsky/bash-on-android)
* [Termux](https://github.com/termux/termux-packages/tree/master/packages/bash)
* [ATechnoHazard and koro666](https://github.com/ATechnoHazard/bash_patches)
* [BlissRoms](https://github.com/BlissRoms/platform_external_bash)

## License

  MIT
