import sys
import os
import json
import hashlib

def get_row(line):
    parts = line.split('|')
    if len(parts) != 2:
        return None
    cpu = int(parts[0].split(')')[0])
    content = parts[1]
    content = content.replace(';', '').replace('{', '').replace('}', '').rstrip()
    if not content:
        return None
    if content[-2:] != '()':
        return None
    depth = content.count('  ') - 1
    func = content.replace('()', '').strip()
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

def get_pattern_md5(pattern):

    content = str([[x['depth'], x['func']] for x in pattern['rows']])
    return hashlib.md5(content.encode()).hexdigest()

def create_svg(puml_path):
    os.system('java -jar thirdparty/plantuml/plantuml-mit.jar -tsvg %s' % puml_path)

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

    if len(sys.argv) < 3 or sys.argv[1] != 'report':
        print('ERROR: Wrong command format.')
        print('/ftrace-chart.sh report --mode=[trace|stack|flame] <input_file>')
        sys.exit(1)

    mode = sys.argv[2].split('=')[1]

    if len(sys.argv) < 4:
        file_path = './result/' + mode + '.data'
    else:
        file_path = os.path.abspath(sys.argv[3])

    if not os.path.isfile(file_path):
        print('ERROR: Input trace file not found: %s' % file_path)
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
        print('> java -jar thirdparty/plantuml/plantuml-mit.jar -tsvg xxx.puml')
        print('------------------------')
        print('%d puml files generated.' % puml_count)
        print('Done.')

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
        create_svg(puml_path)
        print('File generated: %s|.svg' % puml_path)
        print('Done.')

    elif mode == 'flame':
        print('Parsing trace file...')
        os.system('perf script -i %s > %s/flame.script' % (file_path, folder_path))
        os.system('./thirdparty/flamegraph/stackcollapse-perf.pl %s/flame.script > %s/flame.folded' % (folder_path, folder_path))
        os.system('./thirdparty/flamegraph/flamegraph.pl %s/flame.folded --reverse > %s/flame.svg' % (folder_path, folder_path))
        os.system('rm flame.script flame.folded')
        print('File generated: %s/flame.svg' % folder_path)
        print('Done.')

    else:
        print('ERROR: Invalid report mode: --mode=[trace|stack|flame]')
        sys.exit(1)

if __name__ == '__main__':
    main()