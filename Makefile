# contrib/tablelog/Makefile

#MODULE_big = dblink_py
#OBJS	= dblink.o $(WIN32RES)
PG_CPPFLAGS = -I$(libpq_srcdir)
SHLIB_LINK_INTERNAL = $(libpq)

EXTENSION = tablelog
DATA = tablelog--0.1.sql
PGFILEDESC = "tablelog - record table modification logs"

REGRESS = tablelog
REGRESS_OPTS = --dlpath=$(top_builddir)/src/test/regress

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
SHLIB_PREREQS = submake-libpq
subdir = contrib/tablelog
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif

REGRESS_OPTS += --load-extension=plv8
