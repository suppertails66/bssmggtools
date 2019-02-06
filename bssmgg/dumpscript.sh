mkdir -p script/orig

make libsms && make bssmgg_scriptdmp
./bssmgg_scriptdmp bssmgg.gg script/orig/
