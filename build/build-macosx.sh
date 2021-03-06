#!/bin/bash

# ZBS binary directory
BIN_DIR="$(dirname "$PWD")/bin"

# temporary installation directory for dependencies
INSTALL_DIR="$PWD/deps"

# Mac OS X global settings
MACOSX_ARCH="i386"
MACOSX_VERSION="10.6"
MACOSX_SDK_PATH="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.6.sdk"

# number of parallel jobs used for building
MAKEFLAGS="-j4"

# flags for manual building with gcc; build universal binaries for luasocket
MACOSX_FLAGS="-arch $MACOSX_ARCH -mmacosx-version-min=$MACOSX_VERSION -isysroot $MACOSX_SDK_PATH"
BUILD_FLAGS="-O2 -arch x86_64 -dynamiclib -undefined dynamic_lookup $MACOSX_FLAGS -I $INSTALL_DIR/include -L $INSTALL_DIR/lib"

# paths configuration
WXWIDGETS_BASENAME="wxWidgets"
WXWIDGETS_URL="http://svn.wxwidgets.org/svn/wx/wxWidgets/trunk"

LUA_BASENAME="lua-5.1.5"
LUA_FILENAME="$LUA_BASENAME.tar.gz"
LUA_URL="http://www.lua.org/ftp/$LUA_FILENAME"

WXLUA_BASENAME="wxlua"
WXLUA_URL="https://wxlua.svn.sourceforge.net/svnroot/wxlua/trunk"

LUASOCKET_BASENAME="luasocket-2.0.2"
LUASOCKET_FILENAME="$LUASOCKET_BASENAME.tar.gz"
LUASOCKET_URL="http://files.luaforge.net/releases/luasocket/luasocket/luasocket-2.0.2/$LUASOCKET_FILENAME"

# exit if the command line is empty
if [ $# -eq 0 ]; then
  echo "Usage: $0 LIBRARY..."
  exit 0
fi

# iterate through the command line arguments
for ARG in "$@"; do
  case $ARG in
  wxwidgets)
    BUILD_WXWIDGETS=true
    ;;
  lua)
    BUILD_LUA=true
    ;;
  wxlua)
    BUILD_WXLUA=true
    ;;
  luasocket)
    BUILD_LUASOCKET=true
    ;;
  all)
    BUILD_WXWIDGETS=true
    BUILD_LUA=true
    BUILD_WXLUA=true
    BUILD_LUASOCKET=true
    ;;
  *)
    echo "Error: invalid argument $ARG"
    exit 1
    ;;
  esac
done

# check for g++
if [ ! "$(which g++)" ]; then
  echo "Error: g++ isn't found. Please install GNU C++ compiler."
  exit 1
fi

# check for cmake
if [ ! "$(which cmake)" ]; then
  echo "Error: cmake isn't found. Please install CMake and add it to PATH."
  exit 1
fi

# check for svn
if [ ! "$(which svn)" ]; then
  echo "Error: svn isn't found. Please install console SVN client."
  exit 1
fi

# check for wget
if [ ! "$(which wget)" ]; then
  echo "Error: wget isn't found. Please install GNU Wget."
  exit 1
fi

# create the installation directory
mkdir -p "$INSTALL_DIR" || { echo "Error: cannot create directory $INSTALL_DIR"; exit 1; }

# build wxWidgets
if [ $BUILD_WXWIDGETS ]; then
  svn co "$WXWIDGETS_URL" "$WXWIDGETS_BASENAME" || { echo "Error: failed to checkout wxWidgets"; exit 1; }
  cd "$WXWIDGETS_BASENAME"
  ./configure --prefix="$INSTALL_DIR" --disable-debug --disable-shared --enable-unicode \
    --with-libjpeg=builtin --with-libpng=builtin --with-libtiff=no --with-expat=no \
    --with-zlib=builtin --disable-richtext \
    --enable-macosx_arch=$MACOSX_ARCH --with-macosx-version-min=$MACOSX_VERSION --with-macosx-sdk="$MACOSX_SDK_PATH" \
    --with-osx_cocoa CFLAGS="-Os" CXXFLAGS="-Os"
  make $MAKEFLAGS || { echo "Error: failed to build wxWidgets"; exit 1; }
  make install
  cd ..
  rm -rf "$WXWIDGETS_BASENAME"
fi

# build Lua
if [ $BUILD_LUA ]; then
  wget -c "$LUA_URL" -O "$LUA_FILENAME" || { echo "Error: failed to download Lua"; exit 1; }
  tar -xzf "$LUA_FILENAME"
  cd "$LUA_BASENAME"
  sed -i "" 's/PLATS=/& macosx_dylib/' Makefile
  printf "macosx_dylib:\n" >> src/Makefile
  printf "\t\$(MAKE) LUA_A=\"liblua.dylib\" AR=\"\$(CC) -dynamiclib $MACOSX_FLAGS -o\" RANLIB=\"strip -u -r\" \\\\\n" >> src/Makefile
  printf "\tMYCFLAGS=\"-DLUA_USE_LINUX $MACOSX_FLAGS\" MYLDFLAGS=\"$MACOSX_FLAGS\" MYLIBS=\"-lreadline\" lua\n" >> src/Makefile
  printf "\t\$(MAKE) MYCFLAGS=\"-DLUA_USE_LINUX $MACOSX_FLAGS\" MYLDFLAGS=\"$MACOSX_FLAGS\" luac\n" >> src/Makefile
  make macosx_dylib || { echo "Error: failed to build Lua"; exit 1; }
  make install INSTALL_TOP="$INSTALL_DIR"
  strip -u -r "$INSTALL_DIR/bin/lua"
  cp src/liblua.dylib "$INSTALL_DIR/lib"
  [ -f "$INSTALL_DIR/lib/liblua.dylib" ] || { echo "Error: liblua.dylib isn't found"; exit 1; }
  cd ..
  rm -rf "$LUA_FILENAME" "$LUA_BASENAME"
fi

# build wxLua
if [ $BUILD_WXLUA ]; then
  svn co "$WXLUA_URL" "$WXLUA_BASENAME" || { echo "Error: failed to checkout wxLua"; exit 1; }
  cd "$WXLUA_BASENAME/wxLua"
  # the following patches wxlua source to fix live coding support in wxlua apps
  # http://www.mail-archive.com/wxlua-users@lists.sourceforge.net/msg03225.html
  sed -i "" 's/\(m_wxlState = wxLuaState(wxlState.GetLuaState(), wxLUASTATE_GETSTATE|wxLUASTATE_ROOTSTATE);\)/\/\/ removed by ZBS build process \/\/ \1/' modules/wxlua/wxlcallb.cpp
  cmake -G "Unix Makefiles" -DBUILD_INSTALL_PREFIX="$INSTALL_DIR" -DCMAKE_BUILD_TYPE=MinSizeRel -DBUILD_SHARED_LIBS=FALSE \
    -DCMAKE_OSX_ARCHITECTURES=$MACOSX_ARCH -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOSX_VERSION CMAKE_OSX_SYSROOT="$MACOSX_SDK_PATH" \
    -DCMAKE_C_COMPILER=/usr/bin/gcc -DCMAKE_CXX_COMPILER=/usr/bin/g++ -DwxWidgets_CONFIG_EXECUTABLE="$INSTALL_DIR/bin/wx-config" \
    -DwxWidgets_COMPONENTS="stc;html;aui;adv;core;net;base" \
    -DwxLuaBind_COMPONENTS="stc;html;aui;adv;core;net;base" -DwxLua_LUA_LIBRARY_USE_BUILTIN=FALSE \
    -DwxLua_LUA_INCLUDE_DIR="$INSTALL_DIR/include" -DwxLua_LUA_LIBRARY="$INSTALL_DIR/lib/liblua.dylib" .
  (cd modules/luamodule; make $MAKEFLAGS) || { echo "Error: failed to build wxLua"; exit 1; }
  (cd modules/luamodule; make install/strip)
  strip -u -r "$INSTALL_DIR/lib/libwx.dylib"
  [ -f "$INSTALL_DIR/lib/libwx.dylib" ] || { echo "Error: libwx.dylib isn't found"; exit 1; }
  cd ../..
  rm -rf "$WXLUA_BASENAME"
fi

# build LuaSocket
if [ $BUILD_LUASOCKET ]; then
  wget -c "$LUASOCKET_URL" -O "$LUASOCKET_FILENAME" || { echo "Error: failed to download LuaSocket"; exit 1; }
  tar -xzf "$LUASOCKET_FILENAME"
  cd "$LUASOCKET_BASENAME"
  mkdir -p "$INSTALL_DIR/lib/lua/5.1/"{mime,socket}
  gcc $BUILD_FLAGS -o "$INSTALL_DIR/lib/lua/5.1/mime/core.dylib" src/mime.c \
    || { echo "Error: failed to build LuaSocket"; exit 1; }
  gcc $BUILD_FLAGS -o "$INSTALL_DIR/lib/lua/5.1/socket/core.dylib" \
    src/{auxiliar.c,buffer.c,except.c,inet.c,io.c,luasocket.c,options.c,select.c,tcp.c,timeout.c,udp.c,usocket.c} \
    || { echo "Error: failed to build LuaSocket"; exit 1; }
  strip -u -r "$INSTALL_DIR/lib/lua/5.1/mime/core.dylib" "$INSTALL_DIR/lib/lua/5.1/socket/core.dylib"
  mkdir -p "$INSTALL_DIR/share/lua/5.1/socket"
  cp src/{ftp.lua,http.lua,smtp.lua,tp.lua,url.lua} "$INSTALL_DIR/share/lua/5.1/socket"
  cp src/{ltn12.lua,mime.lua,socket.lua} "$INSTALL_DIR/share/lua/5.1"
  [ -f "$INSTALL_DIR/lib/lua/5.1/mime/core.dylib" ] || { echo "Error: mime/core.dylib isn't found"; exit 1; }
  [ -f "$INSTALL_DIR/lib/lua/5.1/socket/core.dylib" ] || { echo "Error: socket/core.dylib isn't found"; exit 1; }
  cd ..
  rm -rf "$LUASOCKET_FILENAME" "$LUASOCKET_BASENAME"
fi

# now copy the compiled dependencies to ZBS binary directory
mkdir -p "$BIN_DIR" || { echo "Error: cannot create directory $BIN_DIR"; exit 1; }
if [ $BUILD_LUA ]; then
  mkdir -p "$BIN_DIR/lua.app/Contents/MacOS"
  cp "$INSTALL_DIR/bin/lua" "$BIN_DIR/lua.app/Contents/MacOS"
  cp "$INSTALL_DIR/bin/lua" "$INSTALL_DIR/lib/liblua.dylib" "$BIN_DIR"
fi
[ $BUILD_WXLUA ] && cp "$INSTALL_DIR/lib/libwx.dylib" "$BIN_DIR"
if [ $BUILD_LUASOCKET ]; then
  mkdir -p "$BIN_DIR/clibs/"{mime,socket}
  cp "$INSTALL_DIR/lib/lua/5.1/mime/core.dylib" "$BIN_DIR/clibs/mime"
  cp "$INSTALL_DIR/lib/lua/5.1/socket/core.dylib" "$BIN_DIR/clibs/socket"
fi

# show a message about successful completion
echo "*** Build has been successfully completed ***"
exit 0
