/*
 * Copyright 2002 Sun Microsystems, Inc.  All rights reserved.
 * Use is subject to license terms.
 *
 * File.xs contains XS code for exacct file manipulation.
 */

#pragma ident	"@(#)File.xs	1.1	02/05/20 SMI"

#include <pwd.h>
#include "../exacct_common.xh"

/* Pull in the file generated by extract_defines. */
#include "FileDefs.xi"

/*
 * The XS code exported to perl is below here.  Note that the XS preprocessor
 * has its own commenting syntax, so all comments from this point on are in
 * that form.
 */

MODULE = Sun::Solaris::Exacct::File PACKAGE = Sun::Solaris::Exacct::File
PROTOTYPES: ENABLE

 #
 # Define the stash pointers if required and create and populate @_Constants.
 #
BOOT:
	{
	init_stashes();
	define_constants(PKGBASE "::File", constants);
	}

 #
 # Open an exacct file and return an object with which to manipulate it.
 # The parameters are the filename, the open mode and a list of optional
 # (key => value) parameters where the key may be  one of creator, aflags or
 # mode.  For a full explanation of the various combinations, see the manpage
 # for ea_open_file(3EXACCT).
 #
ea_file_t *
new(class, name, oflags, ...)
	char	*class;
	char	*name;
	int	oflags;
PREINIT:
	int	i;
	/* Assume usernames are <= 32 chars (pwck(1M) assumes <= 8) */
	char	user[33];
	char	*creator = NULL;
	int	aflags   = -1;
	mode_t	mode     = 0666;
CODE:
	/*
	 * Account for the mandatory parameters,
	 * and the rest must be an even number.
	 */
	i = items - 3;
	if ((i % 2) != 0) {
		croak("Usage: Sun::Solaris::Exacct::File::new"
		    "(class, name, oflags, ...)");
	}

	/* Process any optional parameters. */
	for (i = 3; i < items; i += 2) {
		if (strEQ(SvPV_nolen(ST(i)), "creator")) {
			creator = SvPV_nolen(ST(i + 1));
		} else if (strEQ(SvPV_nolen(ST(i)), "aflags")) {
			aflags = SvIV(ST(i + 1));
		} else if (strEQ(SvPV_nolen(ST(i)), "mode")) {
			mode = SvIV(ST(i + 1));
		} else {
			croak("invalid named argument %s", SvPV_nolen(ST(i)));
		}
	}

	/* Check and default the creator parameter. */
	if (oflags & O_CREAT && creator == NULL) {
		uid_t		uid;
		struct passwd	*pwent;

		uid = getuid();
		if ((pwent = getpwuid(uid)) == NULL) {
			snprintf(user, sizeof (user), "%d", uid);
		} else {
			strlcpy(user, pwent->pw_name, sizeof (user));
		}
		creator = user;
	}

	/* Check and default the aflags parameter. */
	if (aflags == -1) {
		if (oflags == O_RDONLY) {
			aflags = EO_HEAD;
		} else {
			aflags = EO_TAIL;
		}
	}
	RETVAL = ea_alloc(sizeof (ea_file_t));
	PERL_ASSERT(RETVAL != NULL);
	if (ea_open(RETVAL, name, creator, aflags, oflags, mode) == -1) {
		ea_free(RETVAL, sizeof (ea_file_t));
		RETVAL = NULL;
	}
OUTPUT:
	RETVAL

void
DESTROY(self)
	ea_file_t	*self;
CODE:
	ea_close(self);
	ea_free(self, sizeof(ea_file_t));

 #
 # Return the creator of the file.
 #
SV*
creator(self)
	ea_file_t	*self;
PREINIT:
	const char	*creator;
CODE:
	if ((creator = ea_get_creator(self)) == NULL) {
		RETVAL = &PL_sv_undef;
	} else {
		RETVAL = newSVpv(creator, 0);
	}
OUTPUT:
	RETVAL

 #
 # Return the hostname the file was created on.
 #
SV*
hostname(self)
	ea_file_t	*self;
PREINIT:
	const char	*hostname;
CODE:
	if ((hostname = ea_get_hostname(self)) == NULL) {
		RETVAL = &PL_sv_undef;
	} else {
		RETVAL = newSVpv(hostname, 0);
	}
OUTPUT:
	RETVAL

 #
 # Get the next/previous record from the file and return its type.
 # These two operations are so similar that the XSUB ALIAS functionality is
 # used to merge them into one function.
 #
void
next(self)
	ea_file_t	*self;
ALIAS:
	previous = 1
PREINIT:
	ea_object_type_t		type;
	const char			*type_str;
	ea_object_t			object;
	SV				*sv;
	static const char *const	type_map[] =
	    { "EO_NONE", "EO_GROUP", "EO_ITEM" };
PPCODE:
	/* Call the appropriate next/last function. */
	if (ix == 0) {
		type = ea_next_object(self, &object);
	} else {
		type = ea_previous_object(self, &object);
	}

	/* Work out the call context. */
	switch (GIMME_V) {
	case G_SCALAR:
		/* In a scalar context, just return the type. */
		EXTEND(SP, 1);
		if (type == EO_ERROR) {
			PUSHs(&PL_sv_undef);
		} else {
			sv = newSVuv(type);
			sv_setpv(sv, type_map[type]);
			SvIOK_on(sv);
			PUSHs(sv_2mortal(sv));
		}
		break;
	case G_ARRAY:
		/* In a list contect, return the type and catalog. */
		EXTEND(SP, 2);
		if (type == EO_ERROR) {
			PUSHs(&PL_sv_undef);
			PUSHs(&PL_sv_undef);
		} else {
			sv = newSVuv(type);
			sv_setpv(sv, type_map[type]);
			SvIOK_on(sv);
			PUSHs(sv_2mortal(sv));
			PUSHs(sv_2mortal(new_catalog(object.eo_catalog)));
		}
		break;
	case G_VOID:
	default:
		/* In a void context, return nothing. */
		break;
	}

 #
 # Get the next object from the file and return as an ::Object.
 #
SV*
get(self)
	ea_file_t	*self;
PREINIT:
	ea_object_t	*obj;
CODE:
	if ((obj = ea_get_object_tree(self, 1)) != NULL) {
		RETVAL = new_xs_ea_object(obj);
	} else {
		RETVAL = &PL_sv_undef;
	}
OUTPUT:
	RETVAL

 #
 # Write the passed list of ::Objects to the file.
 # Returns true on success and false on failure.
 #
SV*
write(self, ...)
	ea_file_t	*self;
PREINIT:
	int		i;
	SV		*sv;
	HV		*stash;
	ea_object_t	*obj;
CODE:
	for (i = 1; i < items; i++) {
		/* Check the value is either an ::Item or a ::Group. */
		sv = SvRV(ST(i));
		stash = sv ? SvSTASH(sv) : NULL;
		if (stash != Sun_Solaris_Exacct_Object_Item_stash &&
		    stash != Sun_Solaris_Exacct_Object_Group_stash) {
			XSRETURN_NO;
		}

		/* Deflate and write the object. */
		obj = deflate_xs_ea_object(ST(i));
		PERL_ASSERT(obj != NULL);
		if (ea_write_object(self, obj) == -1) {
			XSRETURN_NO;
		}
	}
	RETVAL = &PL_sv_yes;
OUTPUT:
	RETVAL
