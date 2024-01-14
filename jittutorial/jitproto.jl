# This is jullia implementaiton of the jitproto.c
# code from https://github.com/spencertipping/jit-tutorial
# This relies on the exec kwarg for mmap being available, which
# isn't upstreamed yet: https://github.com/fatteneder/julia/tree/fa/prot_exec

using Mmap

mutable struct MachineCode
    const buf::Vector{UInt8}
    offset::Int
    function MachineCode(sz::Int)
        if sz <= 0
            throw(ArgumentError("size must be positive"))
        end
        buf = mmap(Vector{UInt8}, sz, shared=false, exec=true)
        return new(buf, 0)
    end
end

Base.length(a::MachineCode) = length(a.buf)

@inline function Base.write(a::MachineCode, b::UInt8)
    a.offset >= length(a) && return # we are full
    a.offset += 1
    a.buf[a.offset] = b
    return
end

function Base.write(a::MachineCode, bs::UInt8...)
    for b in bs
        write(a, b)
    end
end

struct CompiledMachineCode{RetType,ArgTypes}
    ptr::Ptr{Cvoid}
    function CompiledMachineCode(a::MachineCode,rettype::DataType,argtypes::NTuple{N,DataType}) where N
        ptr = pointer(a.buf)
        new{rettype,Tuple{argtypes...}}(ptr)
    end
end

@generated function call(a::CompiledMachineCode{RetType,ArgTypes}, args...) where {RetType,ArgTypes}
    rettype_ex = Symbol(RetType)
    argtype_ex = Expr(:tuple)
    for t in ArgTypes.types
        push!(argtype_ex.args, Symbol(t))
    end
    arg_ex = [ :(args[$i]) for i in 1:length(args) ]
    ex = quote
        ccall(a.ptr, $rettype_ex, $argtype_ex, $(arg_ex...))
    end
    ex
end

let
    a = MachineCode(4096)
    write(a, 0x48, 0x8b, 0xc7, 0xc3)
    ca = CompiledMachineCode(a, Cint, (Cint,))
    for i = 1:100
        call(ca, Int32(i)) |> println
    end
end
