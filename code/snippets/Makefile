export LD_LIBRARY_PATH := export LD_LIBRARY_PATH=/home/prog/caffe_ristretto/build/lib/:$(LD_LIBRARY_PATH)

CXX=g++
CFLAGS=-c -Wall -std=c++11 -g3 -Ofast -msse2  -I. -I/home/prog/caffe_ristretto/include/ \
		-I/home/prog/caffe_ristretto/src/
LDFLAGS= -L/usr/local/lib -lglog -lgflags -lleveldb -lsnappy -llmdb -lboost_system -lm \
		-lopencv_core -lopencv_highgui -lopencv_imgproc -lboost_thread -lstdc++ -lopenblas \
		-L/home/prog/caffe_ristretto/build/lib/ -lcaffe
KPFLAGS= -DCPU_ONLY=1
SOURCES=${wildcard *.cpp }
OBJECTS=$(SOURCES:.cpp=.o)
EXECUTABLE=class

all: $(SOURCES) $(EXECUTABLE)

clean:
	rm -f *.o
	rm -f $(EXECUTABLE)
	find ./ -name \*.o  -delete

$(EXECUTABLE): $(OBJECTS)
	$(CXX) $(OBJECTS) $(LDFLAGS) -o $@

.cpp.o:
	$(CXX) $(CFLAGS) $(LDFLAGS) $(KPFLAGS) $< -o $@
