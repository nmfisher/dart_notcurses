#!/bin/sh

INLINE_FILE=./lib/src/ffi/notcurses_inline_g.dart

dart run ffigen --config ./ffi/inline.yml

# strip stray typedefs from type-map (bool, Dartbool)
sed -i.bak '/^typedef bool\b/d' ${INLINE_FILE}
sed -i.bak '/^typedef Dartbool\b/d' ${INLINE_FILE}

# fix: bool in NativeFunction signatures is not a valid NativeType
# replace 'bool Function(' inside NativeFunction<...> with 'ffi.Int8 Function('
sed -i.bak 's/NativeFunction<bool Function(/NativeFunction<ffi.Int8 Function(/g' ${INLINE_FILE}
# fix multiline NativeFunction<bool cases (bool on next line after NativeFunction<)
sed -i.bak '/NativeFunction<$/N;s/NativeFunction<\n\s*bool Function/NativeFunction<\n          ffi.Int8 Function/' ${INLINE_FILE}

# remove definitions of Opaque structs because they are in notcurses_g.dart
sed -i.bak '/ffi.Opaque/d' ${INLINE_FILE}

# rename duplicate structs
sed -i.bak 's/\(ncplane\)[0-9]*/\1/g' ${INLINE_FILE}
sed -i.bak 's/\(ncdirect\)[0-9]*/\1/g' ${INLINE_FILE}
sed -i.bak 's/\(nctabbed\)[0-9]*/\1/g' ${INLINE_FILE}
sed -i.bak 's/\(notcurses\)[0-9]*/\1/g' ${INLINE_FILE}

# remove empty lines at the end of the file
sed -i.bak -e :a -e '/^\n*$/{$d;N;ba' -e '}' ${INLINE_FILE}
