import os
import itertools

def generate_words():
    letters = 'abcdefghijklmnopqrstuvwxyz'
    length = 1

    while True:
        for word_tuple in itertools.product(letters, repeat=length):
            yield ''.join(word_tuple)
        length += 1

def generate_equations(number_of_equations : int):
    output = ""
    generator = generate_words()
    for i in range(number_of_equations):
        output += f"{next(generator)} = 0\n"
    
    output = sorted(output.split("\n"))
    output = "\n".join(output)
    print(output)
    return output


script_dir = os.path.dirname(os.path.abspath(__file__))
file_path = os.path.join(script_dir, 'equationSystem.txt')

equations = generate_equations(200)
file = open(file_path, "w")
file.write(equations)