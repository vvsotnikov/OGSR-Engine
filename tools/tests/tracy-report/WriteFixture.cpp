#include "TraceTsv.hpp"

int main(int argc, char** argv)
{
    if (argc != 2) return 1;
    trace_export::TsvFiles output(argv[1]);
    const std::string name = "scope\twith\n\"quotes\" and \xce\xbb";
    output.frame(0, 0, 1000000);
    output.frame(1, 1000000, 2000000);
    output.frame(2, 2000000000, 2000000);
    output.frame(3, 2002000000, 5000000);
    output.zone(name, 2000000000, 2000000, 12345, "worker\t\"one\"\n");
    output.plot(name, 2001000000, 12345678.125);
    output.finish();
}
