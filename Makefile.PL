#
# Copyright 2002 Sun Microsystems, Inc.  All rights reserved.
# Use is subject to license terms.
#
#ident	"@(#)Makefile.PL	1.2	02/09/09 SMI"
#
# Makefile.PL for ::Exacct
#

#
# The various .so files that comprise the ::Exacct module need to be able to
# cross-call each other, and therefore to prevent runtime linker errors it is
# necessary to establish linker dependencies between the various .so files.
#
# This causes several problems.  The first of these is that perl .so files are
# built in one directory (under ../blib in this case) and installed into
# another, so it is necessary to record the dependency using a path relative to
# the dependent. This can be done with the $ORIGIN linker mechanism.

# The second problem is that it is necessary to specify the name of the
# dependee at link edit time in a manner that doesn't result in the build-time
# path of the dependee being hard coded in to the dependent, as this would
# stop ld.so.1 performing its normal search process for the files.  This can't
# be done with the normal '--L/my/lib/path -lmylib' mechanism, because the XSUB
# .so files aren't prefixed with 'lib'.  To do this the -h linker flag is used
# to explicitly set the SONAME in the dependee.  This is then used as the name
# of the dependent in the dependee rather than the full path by which it was
# found at link edit time.
#
# For more details, refer to the Linker and Libraries Guide.
#

require 5.6.1;
use strict;
use warnings;
use ExtUtils::MakeMaker;

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
	    MAN3PODS => { 'pod/Exacct.pod' => $man3pfx . '.$(MAN3EXT)' }
	);
}

WriteMakefile(
    NAME         => 'Sun::Solaris::Exacct',
    VERSION_FROM => 'Exacct.pm',
    DIR          => [ qw(Catalog File Object) ],
    H            => [ 'exacct_common.xh' ],
    LIBS         => [ '-lexacct' ],
    @defines,
    @man3pods,
    dynamic_lib  => { OTHERLDFLAGS => '-h $(DLBASE).$(DLEXT)' },
    realclean    => { FILES => 'ExacctDefs.xi' },
);

package MY;

#
# Force the parent directory to be built first, because the sub-modules all
# have a linker dependency against Exacct.so.
#
sub top_targets
{
	my $self = shift(@_);
	my $txt = $self->SUPER::top_targets(@_);
	$txt =~ s/pm_to_blib subdirs/pm_to_blib \$(LINKTYPE) .WAIT subdirs/;
	return($txt);
}

#
# Make 'install' wait for 'all' to complete.
#
sub install
{
	my $self = shift(@_);
	my $txt = $self->SUPER::install(@_);
	$txt =~ s/all pure_/all .WAIT pure_/g;
	return($txt);
}

#
# Override the default empty 'postamble' sub and replace it with one that
# explicitly records the dependency between Exacct.c (generated from
# Exacct.xs by xsubpp) and the ExacctDefs.xi file (generated from exacct.h and
# sys/exacct.h by extract_defines).  This ensures that the constant values
# exported by the perl module stay up-to date with the corresponding #defines.
#
sub postamble
{
	return <<'EOF';
EXACCT_H=	/usr/include/exacct.h \
		/usr/include/sys/exacct.h

Exacct.c:	ExacctDefs.xi

ExacctDefs.xi:	extract_defines $(EXACCT_H)
	$(PERL) extract_defines $(INC) Exacct $@
EOF
}
