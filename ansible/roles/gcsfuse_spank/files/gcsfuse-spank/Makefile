NAME    := gcsfuse_spank
DESTDIR := /usr/local/lib/slurm

FLAGS   := -ggdb -Wall
SHOPTS  := -shared
LLIBS   := -lslurm
OBJS    := gcsfuse_spank.o

all: $(NAME).so

install:
	mkdir -p --mode=0755 $(DESTDIR)
	install -m0755 $(NAME).so $(DESTDIR)/

$(NAME).so: $(OBJS)
	$(CC) $(SHOPTS) -o $(NAME).so $(OBJS) $(LLIBS)

.c.o:
	$(CC) $(CFLAGS) $(FLAGS) -o $@ -fPIC -c $<

clean:
	-rm -f *.o *.so
