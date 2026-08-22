import numpy


if "bool" not in numpy.__dict__:
    numpy.bool = bool

if "string_" not in numpy.__dict__:
    numpy.string_ = numpy.bytes_

from qpython import qconnection