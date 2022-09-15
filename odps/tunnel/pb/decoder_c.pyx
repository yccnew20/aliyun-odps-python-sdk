# -*- coding: utf-8 -*-
# Copyright 1999-2022 Alibaba Group Holding Ltd.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

include "util_c.pxi"

from libc.stdint cimport *
from libc.string cimport *

from wire_format import TAG_TYPE_BITS as PY_TAG_TYPE_BITS, _TAG_TYPE_MASK as _PY_TAG_TYPE_MASK

cdef:
    int TAG_TYPE_BITS = PY_TAG_TYPE_BITS
    int _TAG_TYPE_MASK = _PY_TAG_TYPE_MASK
    size_t _BUFFER_SIZE = 64 * 1024
    size_t _MIN_SERIALIZED_INT_SIZE = 10  # ceil(64 / 7)


cdef class Decoder:

    def __cinit__(self, stream):
        self._pos = 0
        self._stream = stream
        self._buffer = stream.read(_BUFFER_SIZE)
        self._begin = self._buffer
        self._end = self._begin + len(self._buffer)
        self._is_source_eof = False

    cpdef int32_t read_field_number(self) except? -1:
        if self._is_eof():
            raise EOFError
        if self._end - self._begin < _MIN_SERIALIZED_INT_SIZE:
            self._load_next_buffer()

        cdef int32_t tag_and_type
        tag_and_type = self.read_uint32()
        return tag_and_type >> TAG_TYPE_BITS

    cpdef read_field_number_and_wire_type(self):
        if self._is_eof():
            raise EOFError
        if self._end - self._begin < _MIN_SERIALIZED_INT_SIZE:
            self._load_next_buffer()

        cdef int32_t tag_and_type
        tag_and_type = self.read_uint32()
        return (tag_and_type >> TAG_TYPE_BITS), (tag_and_type & _TAG_TYPE_MASK)

    def __len__(self):
        return self._pos

    cpdef size_t position(self):
        return self._pos

    cpdef int32_t read_sint32(self) except? -1:
        if self._is_eof():
            raise EOFError
        if self._end - self._begin < _MIN_SERIALIZED_INT_SIZE:
            self._load_next_buffer()
        return get_signed_varint32(&self._begin, self._end, &self._pos)

    cpdef uint32_t read_uint32(self) except? 0xffffffff:
        if self._is_eof():
            raise EOFError
        if self._end - self._begin < _MIN_SERIALIZED_INT_SIZE:
            self._load_next_buffer()
        return get_varint32(&self._begin, self._end, &self._pos)

    cpdef int64_t read_sint64(self) except? -1:
        if self._is_eof():
            raise EOFError
        if self._end - self._begin < _MIN_SERIALIZED_INT_SIZE:
            self._load_next_buffer()
        return get_signed_varint64(&self._begin, self._end, &self._pos)

    cpdef uint64_t read_uint64(self) except? 0xffffffff:
        if self._is_eof():
            raise EOFError
        if self._end - self._begin < _MIN_SERIALIZED_INT_SIZE:
            self._load_next_buffer()
        return get_varint64(&self._begin, self._end, &self._pos)

    cpdef bint read_bool(self) except? False:
        if self._is_eof():
            raise EOFError
        if self._end - self._begin < _MIN_SERIALIZED_INT_SIZE:
            self._load_next_buffer()
        return get_varint32(&self._begin, self._end, &self._pos)

    cpdef double read_double(self) except? -1.0:
        cdef double retval

        if self._is_eof():
            raise EOFError
        if self._end - self._begin < sizeof(double):
            self._load_next_buffer()

        memcpy(&retval, self._begin, sizeof(double))
        self._begin += sizeof(double)
        self._pos += sizeof(double)
        return retval

    cpdef float read_float(self) except? -1.0:
        cdef float retval

        if self._is_eof():
            raise EOFError
        if self._end - self._begin < sizeof(float):
            self._load_next_buffer()
        memcpy(&retval, self._begin, sizeof(float))
        self._begin += sizeof(float)
        self._pos += sizeof(float)
        return retval

    cpdef bytes read_string(self):
        cdef size_t size

        if self._is_eof():
            raise EOFError
        if self._end - self._begin < _MIN_SERIALIZED_INT_SIZE:
            self._load_next_buffer()
        size = self.read_uint32()

        cdef int need = size
        cdef int offset
        cdef list result = []
        cdef bytes chunk
        while need > 0:
            if need > self._end - self._begin:
                self._load_next_buffer()
            if need > self._end - self._begin:
                # _load_next_buffer() will put unused buffer at head after invoked
                chunk = self._buffer
                self._pos += self._end - self._begin
                need -= self._end - self._begin
                self._begin = self._end
                result.append(chunk)
                continue

            offset = len(self._buffer) - (self._end - self._begin)
            chunk = self._buffer[offset:offset+need]
            self._begin += need
            self._pos += need
            result.append(chunk)
            need = 0

        if len(result) == 0:
            return b''
        elif len(result) == 1:
            return result[0]
        else:
            return b''.join(result)

    cdef int _load_next_buffer(self) except -1:
        cdef bytes data = self._stream.read(_BUFFER_SIZE)
        cdef size_t length = len(data)
        if length == 0:
            self._is_source_eof = True
            return 0

        cdef bytes left
        if self._end - self._begin > 0:
            left = self._buffer[self._begin - self._end:]
            self._buffer = left + data
        else:
            self._buffer = data

        self._begin = self._buffer
        self._end = self._begin + len(self._buffer)
        return 0

    cdef bint _is_eof(self):
        return self._is_source_eof and (self._begin >= self._end)
