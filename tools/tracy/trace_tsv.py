"""Strict TSV structure, with lossless decoding of legacy source-path bytes."""
import csv
import math

HEADERS = {
    'frames': ['index', 'start_ns', 'duration_ns'],
    'zones': ['name', 'start_ns', 'duration_ns', 'thread_id', 'thread_name', 'source_id', 'file', 'line'],
    'plots': ['type', 'name', 'time_ns', 'value'],
}

CONVERTERS = {
    'frames': [int, int, int],
    'zones': [str, int, int, int, str, int, str, int],
    'plots': [str, str, int, float],
}


def rows(prefix, kind):
    expected = HEADERS[kind]
    path = prefix + '-' + kind + '.tsv'
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as source:
        reader = csv.reader(source, delimiter='\t', strict=True)
        try:
            if next(reader, None) != expected:
                raise ValueError(f'Unexpected {kind} schema (or empty file)')
            for row in reader:
                if len(row) != len(expected):
                    raise ValueError(f'Invalid {kind} row at line {reader.line_num}')
                converted = []
                for column, value, convert in zip(expected, row, CONVERTERS[kind]):
                    try:
                        value = convert(value)
                        if isinstance(value, float) and not math.isfinite(value):
                            raise ValueError('non-finite value')
                    except ValueError as error:
                        raise ValueError(f'{path}: invalid {column} at line {reader.line_num}: {error}') from error
                    converted.append(value)
                yield converted
        except csv.Error as error:
            raise ValueError(f'Invalid {kind} TSV at line {reader.line_num}: {error}') from error
