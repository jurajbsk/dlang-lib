module lib.memory;
version(LDC) import ldc.attributes;
else {
	struct allocSize {long sizeArgIdx; long numArgIdx;}
}

@safe nothrow pure:
uint getPageSize()
{
	version(Windows) {
		import lib.sys.windows.kernel32;
		SYSTEM_INFO si;
		GetSystemInfo(si);
		uint res = si.pageSize;
	}
	return res;
}
size_t roundToPage(size_t size)
{
	return (size + getPageSize-1)/getPageSize;
}

@allocSize(0) void* _malloc(size_t size) @trusted
{
	version(Windows) {
		void* ptr = VirtualAlloc(null, size, COMMIT, READWRITE);
	}
	return ptr;
}
/// Returns allocated memory, minimum size specified by the argument
T[] malloc(T)(size_t size = 1) @trusted
{
	//static if(is(T : immutable dchar)) size++;

	T* ptr = cast(T*) _malloc(size * T.sizeof);
	return ptr[0..size];
}

@allocSize(1) void* _realloc(void* ptr, size_t size, size_t cursize) @trusted
{
	void* olddata = _alloca(cursize);
	olddata[0..cursize] = ptr[0..cursize];
	free(ptr);

	void* newptr = _malloc(size);
	if(olddata && olddata != newptr) {
		newptr[0..cursize] = olddata[0..cursize];
	}
	return newptr;
}
/// Reallocates memory
T[] realloc(T)(T[] block, size_t size) @trusted
{
	if(block.length >= size) return block[0..size];
	
	T* ptr = cast(T*) _realloc(block.ptr, roundToPage(size*T.sizeof), roundToPage(block.length*T.sizeof));
	return ptr[0..size];
}
/// Frees allocated memory
void free(void* block) @trusted
{
	version(Windows) {
		enum : uint {
			DECOMMIT = 0X4000,
			RELEASE = 0X8000
		}
		bool errCode = VirtualFree(block, 0, RELEASE);
	}
}
version(LDC) pragma(LDC_alloca) void* _alloca(size_t size) @trusted pure;
/// Allocates memory on the stack, freed when function
T[] alloca(T)(size_t size) @trusted
{
	version(LDC) {
	T* ptr = cast(T*) _alloca(size * T.sizeof);
	return ptr[0..size];
	}
	else static assert(0, "Sorry bud, you'll need LDC2 to use alloca()");
}

nothrow __gshared:
version(Windows) extern(Windows) {
	void* VirtualAlloc(void* startAddress=null, size_t size, uint allocFlag, uint protectFlag);
	enum : uint {
		COMMIT = 0x1000,
		RESERVE = 0x2000
	}
	enum : uint {
		NOACCESS = 0x1,
		READONLY = 0x2,
		READWRITE = 0x4
	}
	bool VirtualFree(const void* address, size_t size = 0, uint flags);
}
else version(Posix) extern(C)
{
	void* mmap64(void*, size_t, int, int, int, long);
	void* mmap(void*, size_t, int, int, int, long);
}

unittest
{
	int[] foo = malloc!int(3);
	assert(foo.length == 3);
	foo = realloc(foo, 1);
	assert(foo.length == 1);

	long[] bar = malloc!long(getPageSize*2);
	long* barptr = &bar[0];
	bar = realloc(bar, getPageSize+1);
	assert(&bar[0] == barptr);

	bar = realloc(bar, getPageSize*3);
	bar[$-1] = 5;
	assert(bar[getPageSize*3-1] == 5);
}