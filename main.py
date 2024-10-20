import sys
import os
import json
import hashlib

pendings = dict()
writtens = list()

def get_row(line):
    if len(line) <= 3 or line[3] != ')':
        return None
    cpu = int(line[0:3])
    line = line[21:].replace(';', '').replace('{', '').replace('}', '').rstrip()
    if not line:
        return None
    if line[-2:] != '()':
        return None
    depth = line.count('  ')
    func = line.replace('()', '').strip()
    row = {
        'cpu': cpu,
        'func': func,
        'depth': depth
    }
    return row

def create_pattern_puml(puml_path, pattern):
    with open(puml_path, 'w') as file:
        file.write('@startmindmap\n')
        for row in pattern['rows']:
            line = (row['depth'] + 1) * '+' + ' ' + row['func'] + '()\n'
            file.write(line)
        file.write('@endmindmap\n')

def create_pattern_svg(puml_path):
    os.system('java -jar plantuml-mit.jar -tsvg %s' % puml_path)

def get_pattern_md5(pattern):

    content = str([[x['depth'], x['func']] for x in pattern['rows']])
    return hashlib.md5(content.encode()).hexdigest()

def main():
    if len(sys.argv) < 3:
        print("./ftrace-chart.sh report trace_file")
        sys.exit(1)

    file_path = os.path.abspath(sys.argv[2])

    if not os.path.isfile(file_path):
        print("ERROR: Input trace file not found. %s" % file_path)
        sys.exit(1)

    folder_path = os.path.dirname(file_path)

    puml_count = 0
    with open(file_path, 'r') as file:
        for line in file:
            row = get_row(line)
            if not row:
                continue
            cpu = row['cpu']
            if row['depth'] == 0:
                if cpu in pendings:
                    pattern = pendings[cpu]
                    md5 = get_pattern_md5(pattern)
                    if md5 not in writtens:
                        writtens.append(md5)
                        puml_path = folder_path + '/' + pattern['func'] + '~' + str((len(writtens) - 1)) + '.puml'
                        create_pattern_puml(puml_path, pattern)
                        puml_count += 1
                    del pendings[cpu]
                pendings[cpu] = {'cpu': row['cpu'], 'func': row['func'], 'rows': [row]}
            else:
                if cpu not in pendings:
                    continue
                pendings[cpu]['rows'].append(row)

    print('------------------------')
    print('To generate a svg chart image:')
    print('> java -jar plantuml-mit.jar -tsvg xxx.puml')
    print('------------------------')
    print('Success, %d puml files generated.' % puml_count)

if __name__ == '__main__':
    main()