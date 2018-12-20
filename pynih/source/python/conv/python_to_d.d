module python.conv.python_to_d;


import python.raw: PyObject;
import python.type: isUserAggregate, isTuple;
import std.traits: Unqual, isIntegral, isFloatingPoint, isAggregateType, isArray,
    isStaticArray, isAssociativeArray, isPointer, PointerTarget;
import std.range: isInputRange;
import std.datetime: DateTime, Date;


T to(T)(PyObject* value) @trusted if(isIntegral!T) {
    import python.raw: PyLong_AsLong;

    const ret = PyLong_AsLong(value);
    if(ret > T.max || ret < T.min) throw new Exception("Overflow");

    return cast(T) ret;
}


T to(T)(PyObject* value) @trusted if(isFloatingPoint!T) {
    import python.raw: PyFloat_AsDouble;
    auto ret = PyFloat_AsDouble(value);
    return cast(T) ret;
}


T to(T)(PyObject* value) if(isUserAggregate!T) {
    import python.type: PythonClass;

    auto pyclass = cast(PythonClass!T*) value;

    Unqual!T ret;

    static if(__traits(compiles, ret is null)) {
        if(ret is null) return ret;
    }

    static foreach(i; 0 .. T.tupleof.length) {
        ret.tupleof[i] = pyclass.getField!i.to!(typeof(T.tupleof[i]));
    }

    return ret;
}


T to(T)(PyObject* value) if(isPointer!T && isUserAggregate!(PointerTarget!T)) {
    auto ret = new Unqual!(PointerTarget!T);
    *ret = to!(PointerTarget!T)(value);
    return ret;
}


T to(T)(PyObject* value) if(is(Unqual!T == DateTime)) {
    import python.raw;

    return DateTime(pyDateTimeYear(value),
                    pyDateTimeMonth(value),
                    pyDateTimeDay(value),
                    pyDateTimeHour(value),
                    pyDateTimeMinute(value),
                    pyDateTimeSecond(value));

}


T to(T)(PyObject* value) if(is(Unqual!T == Date)) {
    import python.raw;

    return Date(pyDateTimeYear(value),
                pyDateTimeMonth(value),
                pyDateTimeDay(value));
}


T to(T)(PyObject* value) if(isArray!T && !is(Unqual!T == string)) {
    import python.raw: PyList_Size, PyList_GetItem;
    import std.range: ElementType;

    T ret;
    static if(__traits(compiles, ret.length = 1))
        ret.length = PyList_Size(value);

    foreach(i, ref elt; ret) {
        elt = PyList_GetItem(value, i).to!(ElementType!T);
    }

    return ret;
}


T to(T)(PyObject* value) if(is(Unqual!T == string)) {
    import python.raw: pyUnicodeGetSize, pyUnicodeCheck,
        pyBytesAsString, pyObjectUnicode, pyUnicodeAsUtf8String, Py_ssize_t;

    value = pyObjectUnicode(value);

    const length = pyUnicodeGetSize(value);

    auto ptr = pyBytesAsString(pyUnicodeAsUtf8String(value));
    assert(length == 0 || ptr !is null);

    return ptr[0 .. length].idup;
}


T to(T)(PyObject* value) if(is(Unqual!T == bool)) {
    import python.raw: pyTrue;
    return value is pyTrue;
}



T to(T)(PyObject* value) if(isAssociativeArray!T)
{
    import python.raw: pyDictCheck, PyDict_Keys, PyList_Size, PyList_GetItem, PyDict_GetItem;

    assert(pyDictCheck(value));

    // this enum is to get K and V whilst avoiding auto-decoding, which is why we're not using
    // std.traits
    enum _ = is(T == V[K], V, K);
    alias KeyType = Unqual!K;
    alias ValueType = Unqual!V;

    ValueType[KeyType] ret;

    auto keys = PyDict_Keys(value);

    foreach(i; 0 .. PyList_Size(keys)) {
        auto k = PyList_GetItem(keys, i);
        auto v = PyDict_GetItem(value, k);
        auto dk = k.to!KeyType;
        auto dv = v.to!ValueType;

        version(unittest) {
            import unit_threaded.io;
            writelnUt("dkey: ", dk, "  dvalue: ", dv);
        }

        ret[dk] = dv;
    }

    return ret;
}


T to(T)(PyObject* value) if(isTuple!T) {
    import python.raw: pyTupleCheck, PyTuple_Size, PyTuple_GetItem;

    assert(pyTupleCheck(value));
    assert(PyTuple_Size(value) == T.length);

    T ret;

    static foreach(i; 0 .. T.length) {
        ret[i] = PyTuple_GetItem(value, i).to!(typeof(ret[i]));
    }

    return ret;
}
