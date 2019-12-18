INCLUDE=-I/usr/include/lua5.2/ -Iluwra/lib/ -Ihungarian
LIBOPTS="-shared"
FLAGS=-fpic -std=c++11
CXX="g++"

munkres.so: munkres.cpp hungarian/hungarian.cpp
	$(CXX) $^ $(INCLUDE) $(FLAGS) $(LIBOPTS) -o $@


all: munkres.so

clean:
	rm -f munkres.so
