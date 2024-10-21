import sys
import os
import json
import hashlib

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


def merge_stack(stackmap, pending):
    level = stackmap
    for func in pending['stack']:
        if func not in level:
            level[func] = dict()
        level = level[func]

def create_stackmap_puml(puml_path, stackmap):

    with open(puml_path, 'w') as file:
        file.write('@startmindmap\n')
        stack = [(stackmap, [])]
        while stack:
            cur_dict, cur_path = stack.pop()
            if cur_path:
                func = str(cur_path[-1])
                file.write((len(cur_path)) * '-' + ' ' + func + '()\n')
            for key, val in reversed(cur_dict.items()):
                path = cur_path + [key]
                stack.append((val, path))
        file.write('@endmindmap\n')

def main():

    if len(sys.argv) < 4:
        print('ERROR: Wrong command format.')
        print('/ftrace-chart.sh report --mode=[trace|stack] <trace file>)')
        sys.exit(1)

    mode = sys.argv[2].split('=')[1]

    file_path = os.path.abspath(sys.argv[3])

    if not os.path.isfile(file_path):
        print('ERROR: Input trace file not found. %s' % file_path)
        sys.exit(1)

    folder_path = os.path.dirname(file_path)

    if mode == 'trace':
        print('Parsing trace file...')
        pendings = dict()
        writtens = list()
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
    elif mode == 'stack':
        print('Parsing trace file...')
        stackmap = dict()
        pending = None
        with open(file_path, 'r') as file:
            for line in file:
                if line[1:3] == '=>':
                    func = line.split()[1]
                    if not pending:
                        continue
                    if pending['func'] is None:
                        pending['func'] = func
                    pending['stack'].append(func)
                elif '<stack trace>' in line:
                    if pending:
                        merge_stack(stackmap, pending)
                        #print(pending)
                        pending = None
                    pending = {'func': None, 'stack': list()}
                else:
                    continue

        if not stackmap:
            print('Nothing generated.')
            sys.exit(0)
        func = list(stackmap.keys())[0]
        puml_path = folder_path + '/' + func + '.puml'
        create_stackmap_puml(puml_path, stackmap)
        print('------------------------')
        print('To generate a svg chart image:')
        print('> java -jar plantuml-mit.jar -tsvg xxx.puml')
        print('------------------------')
        print('Success. (%s)' % puml_path)
    else:
        print('ERROR: Invalid report mode: --mode=[trace|stack]')
        sys.exit(1)

if __name__ == '__main__':
    main()