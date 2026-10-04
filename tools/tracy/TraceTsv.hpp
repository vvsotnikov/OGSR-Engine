#pragma once

#include <cstdint>
#include <fstream>
#include <iomanip>
#include <limits>
#include <stdexcept>
#include <string>

namespace trace_export
{
inline void write_name(std::ostream& out, const std::string& name)
{
    out << '"';
    for (const char c : name)
    {
        if (c == '"') out << '"';
        out << c;
    }
    out << '"';
}

class TsvFiles
{
    std::string prefix;
    std::ofstream frames, zones, plots;

public:
    explicit TsvFiles(const std::string& output_prefix)
        : prefix(output_prefix),
          frames(prefix + "-frames.tsv", std::ios::binary),
          zones(prefix + "-zones.tsv", std::ios::binary),
          plots(prefix + "-plots.tsv", std::ios::binary)
    {
        if (!frames || !zones || !plots)
            throw std::runtime_error("Cannot open output files for prefix: " + prefix);
        frames << "index\tstart_ns\tduration_ns\n";
        zones << "name\tstart_ns\tduration_ns\tthread_id\tthread_name\tsource_id\tfile\tline\n";
        plots << "name\ttime_ns\tvalue\n" << std::setprecision(std::numeric_limits<double>::max_digits10);
    }

    void frame(uint64_t index, int64_t start, int64_t duration)
    {
        frames << index << '\t' << start << '\t' << duration << '\n';
    }

    void zone(const std::string& name, int64_t start, int64_t duration,
              uint64_t thread_id, const std::string& thread_name,
              int64_t source_id, const std::string& file, unsigned line)
    {
        write_name(zones, name);
        zones << '\t' << start << '\t' << duration << '\t' << thread_id << '\t';
        write_name(zones, thread_name);
        zones << '\t' << source_id << '\t';
        write_name(zones, file);
        zones << '\t' << line << '\n';
    }

    void plot(const std::string& name, int64_t time, double value)
    {
        write_name(plots, name);
        plots << '\t' << time << '\t' << value << '\n';
    }

    void finish()
    {
        frames.flush(); zones.flush(); plots.flush();
        if (!frames || !zones || !plots)
            throw std::runtime_error("Failed writing output files for prefix: " + prefix);
    }
};
}
