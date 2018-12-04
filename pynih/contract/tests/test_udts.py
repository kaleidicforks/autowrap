# coding=utf8
import pytest


def test_simple_struct_func():
    from contract import simple_struct_func
    mytype = simple_struct_func()
    assert mytype.the_int == 42
    assert mytype.the_double == 33.3


def test_twice_struct_func():
    from contract import twice_struct_func
    s3 = twice_struct_func(3)
    assert s3.twice() == 6
    s4 = twice_struct_func(4)
    assert s4.twice() == 8


def test_struct_getset():
    from contract import struct_getset
    s = struct_getset()
    # no setter for i
    with pytest.raises(AttributeError):
        s.i = 0

    # this always returns 42 no matter what
    assert s.i == 42

    # getter and setter for d
    s.d = 33.3
    assert s.d == 33.3
    s.d = 44.4
    assert s.d == 44.4

    assert s.inner.i == 999
    s.inner.i = 21
    assert s.inner.i == 21
    s.inner.i = 22
    assert s.inner.i == 22

    assert s.inner.d == 777.77
    s.inner.d = 55.5
    assert s.inner.d == 55.5


# def test_ctor():
#     from contract import MyStruct

#     assert MyStruct().i == 42
#     # TODO
#     # assert MyStruct(77).i == 77
