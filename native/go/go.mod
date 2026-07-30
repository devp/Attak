module github.com/devp/attak/native/go

go 1.21

// Taktician is not tagged, so this is a pseudo-version pinned to an exact commit
// -- both for reproducible builds and so the binary can be traced to the source
// that produced it.
require github.com/nelhage/taktician v0.0.0-20240227154445-7af1aca31945
