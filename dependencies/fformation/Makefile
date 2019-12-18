.DEFAULT_GOAL := all

base/Makefile: base
	cmake base/CMakeLists.txt -DCMAKE_INSTALL_PREFIX=install

install/lib/libfformation.so: base/Makefile
	make -C base install

gco:
	git clone --recursive https://github.com/vrichter/fformation-gco.git gco

gco/Makefile: install/lib/libfformation.so
	cmake gco/CMakeLists.txt -DCMAKE_INSTALL_PREFIX=install -DBUILD_LUA_BINDING=ON

install/lib/libfformation-gco_lua.so: gco/Makefile
	make -C gco install

../../libfformation-gco_lua.so: install/lib/libfformation-gco_lua.so
	ln -s dependencies/fformation/install/lib/libfformation-gco_lua.so ../../libfformation-gco_lua.so

all: ../../libfformation-gco_lua.so

clean:
	make -C base clean
	make -C gco clean
	rm -rf install
	rm -f ../../libfformation-gco_lua.so
