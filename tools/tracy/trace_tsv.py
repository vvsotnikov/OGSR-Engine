"""Strict TSV structure, with lossless decoding of legacy source-path bytes."""
import csv

HEADERS = {
    'frames': ['index', 'start_ns', 'duration_ns'],
    'zones': ['name', 'start_ns', 'duration_ns', 'thread_id', 'thread_name', 'source_id', 'file', 'line'],
    'plots': ['type', 'name', 'time_ns', 'value'],
}


def rows(prefix, kind):
    expected = HEADERS[kind]
    with open(prefix + '-' + kind + '.tsv', encoding='utf-8', errors='surrogateescape', newline='') as source:
        reader = csv.reader(source, delimiter='\t', strict=True)
        try:
            if next(reader, None) != expected:
                raise ValueError(f'Unexpected {kind} schema (or empty file)')
            for row in reader:
                if len(row) != len(expected):
                    raise ValueError(f'Invalid {kind} row at line {reader.line_num}')
                yield row
        except csv.Error as error:
            raise ValueError(f'Invalid {kind} TSV at line {reader.line_num}: {error}') from error
