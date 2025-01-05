import os

script_dir = os.path.dirname(os.path.abspath(__file__))
file_path = os.path.join(script_dir, 'equationSystem.txt')

file = open(file_path, "w")


for i in range(45000):
    file.write(f"x{i} + b = 0\n")