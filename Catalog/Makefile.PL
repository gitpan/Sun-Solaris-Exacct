#
# Copyright 2002-2003 Sun Microsystems, Inc.  All rights reserved.
# Use is subject to license terms.
#
#ident	"@(#)Makefile.PL	1.3	03/03/13 SMI"
#
# Makefile.PL for ::Exacct::Catalog
#

# See ../Makefile.PL for an explanation of the linker flag manipulations.

require 5.6.1;
use strict;
use warnings;
use ExtUtils::MakeMaker;

#
# Some later versions of ExtUtils::MakeMaker are broken,
# and complain about function redefinitions in the child Makefile.PLs.
# Stop the warnings.
#
no warnings qw(redefine);

# #defines.
my @defines = ( DEFINE => exists($ENV{RELEASE_BUILD}) ? '-DNDEBUG' : '' );

# List of POD pages to install.
my @man3pods = ( MAN3PODS => {} );

#
# If not building as part of ON.
#
if (! exists($ENV{CODEMGR_WS})) {

	#
	# Suppress the setting of LD_RUN_PATH.  The ON build environment
	# contains a modified MakeMaker that does this automatically, so we
	# only need to do this if we are building outside of ON.
	#
	package MY;
	no warnings qw(once);

	# Override const_loadlibs to remove LD_RUN_PATH cruft.
	*const_loadlibs = sub
	{
		my $self = shift(@_);
		delete($self->{LD_RUN_PATH});
		return($self->SUPER::const_loadlibs(@_));
	};

	# Override dynamic_lib to get rid of LD_RUN_PATH cruft.
	*dynamic_lib = sub
	{
		my $self = shift(@_);
		my $txt = $self->SUPER::dynamic_lib(@_);
		$txt =~ s/LD_RUN_PATH=\S*\s*//;
		return($txt);
	};

	# Turn off debugging.
	@defines = ();

	#
	# Install the POD documentation for non-ON builds.
	#
	my $man3pfx = '$(INST_MAN3DIR)/Sun::Solaris::Exacct';
	@man3pods = (
	    MAN3PODS => { '../pod/Catalog.pod' =>
	    $man3pfx . '::Catalog.$(MAN3EXT)' },
	);
}

WriteMakefile(
    NAME         => 'Sun::Solaris::Exacct::Catalog',
    VERSION_FROM => 'Catalog.pm',
    H            => [ '../exacct_common.xh' ],
    TYPEMAPS     => [ '../typemap' ],
    @defines,
    @man3pods,
    dynamic_lib  => { OTHERLDFLAGS =>
        '-h $(DLBASE).$(DLEXT) ' .
        '-R\$$ORIGIN/.. $(INST_ARCHAUTODIR)/../Exacct.so'
	},
    realclean    => { FILES => 'CatalogDefs.xi' },
);

package MY;

#
# Override the default empty 'postamble' sub and replace it with one that
# explicitly records the dependency between Catalog.c (generated from
# Catalog.xs by xsubpp) and the CatalogDefs.xi file (generated from
# exacct_catalog.h by extract_defines).  This ensures that the constant values
# exported by the perl module stay up-to date with the corresponding #defines.
#
sub postamble
{
return <<'EOF';
EXACCT_H=	/usr/include/sys/exacct_catalog.h

Catalog.c:	CatalogDefs.xi

CatalogDefs.xi:	../extract_defines $(EXACCT_H)
	$(PERL) ../extract_defines $(INC) Catalog $@
EOF
}
