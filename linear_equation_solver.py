import re
import tkinter as tk
import subprocess
import sys
import ctypes
from enum import Enum
from typing import Tuple, Callable
from tkinter import ttk, filedialog, scrolledtext, messagebox

class LibraryEnum(Enum):
    C_LIB = 1
    ASM_LIB = 2


class LinearEquationSolver:
    def __init__(self, num_threads : int, lib : LibraryEnum):
        self._num_threads = num_threads
        if lib == LibraryEnum.C_LIB:
            self._solver_dll = ctypes.cdll.LoadLibrary(r"./Lib/LinSysSolverLib.dll")
        elif lib == LibraryEnum.ASM_LIB:
            print("ASM")
        else:
            print("none?")

        self._solver_dll.solve_linear_system.argtypes = [
            ctypes.POINTER(ctypes.c_double), 
            ctypes.c_int,
            ctypes.c_int
        ]
        self._solver_dll.solve_linear_system.restype = ctypes.c_int

    def _flatten_matrix(self, matrix_data : list) -> list:
        flattened_data = []
        for row in matrix_data:
            flattened_data.extend(row)

        return flattened_data

    def solve(self, matrix_data : list) -> list:
        sizeY = len(matrix_data)
        sizeX = len(matrix_data[0])

        flattened_data = self._flatten_matrix(matrix_data)

        DoubleArrayType = ctypes.c_double * (sizeX * sizeY)
        c_matrix = DoubleArrayType(*flattened_data)

        res = self._solver_dll.solve_linear_system(c_matrix, sizeY, sizeX)
        
        # TODO IMPLEMENT ERROR HANDLING AND SOLVING AND DISPLAYING DATA, THEN ADD MULTITHREADING AND ASSEMBLY LIB

        updated_data = list(c_matrix)

def parse_linear_equation(equation : str) -> dict:
    equation = equation.replace(" ", "")
    
    if equation.count('=') != 1:
        raise ValueError(f"Equation {equation} must contain only one = sign.")
    left_side, right_side = equation.split('=')
    
    def parse_side(side):
        side = side.replace('--', '+').replace('-', '+-')
        
        terms = side.split('+')
        terms = [t for t in terms if t and t != '-']
        
        pattern = re.compile(r'^([+-]?[\d]*\.?[\d]*)([\w]*)$')
        
        parsed = {}
        for term in terms:
            match = pattern.match(term)
            if not match:
                raise ValueError(f"Invalid term '{term}' in equation.")
            
            num_str, var_str = match.groups()
            
            if num_str in ['+', '']:
                coeff = 1.0
            elif num_str == '-':
                coeff = -1.0
            else:
                coeff = float(num_str)
            
            parsed[var_str] = parsed.get(var_str, 0.0) + coeff

        return parsed

    left_parsed = parse_side(left_side)
    right_parsed = parse_side(right_side)

    for var, val in right_parsed.items():
        left_parsed[var] = left_parsed.get(var, 0) - val

    return left_parsed


def parse_linear_equations(equations : str) -> list:
    if not equations:
        raise ValueError("No equations given.")

    equations = equations.split('\n')
    equations = [line for line in equations if line.strip()]
    
    parsed = []
    for equation in equations:
        parsed.append(parse_linear_equation(equation))
    
    return parsed


def equations_to_matrix(equations) :
    variables = set()
    for eq in equations:
        for var in eq.keys():
            if var != '':
                variables.add(var)
    variables = sorted(variables)

    matrix = []
    for eq in equations:
        row = [0] * (len(variables) + 1)
        for var, coef in eq.items():
            if var == '':
                row[-1] = -coef
            else:
                idx = variables.index(var)
                row[idx] = coef

        matrix.append(row)

    return matrix, variables


class MenuFrame(ttk.Frame):
    def __init__(self, 
                 parent : tk.Widget, 
                 menu_title : str, 
                 padding : Tuple[int, int] = (10, 10),
                 title_font : Tuple[str, int] = ('Arial', 12)):
        super().__init__(parent)
        self['relief'] = 'groove'
        self.titleLabel = ttk.Label(self, text=menu_title, font=title_font)
        self.titleLabel.pack(fill='x',  padx=padding[0], pady=padding[1])


class RadioFrame(MenuFrame):  
    def __init__(self, parent : tk.Widget,
                 title : str,
                 radio_options : Tuple[Tuple[str, Callable[[], None]], ...],
                 padding : Tuple[int, int] = (10, 10),
                 title_font : Tuple[str, int] = ('Arial', 12)):
        
        if not radio_options:
            raise ValueError("radio_options cannot be empty.")

        # init frame
        super().__init__(parent, title, padding, title_font)

        # set default value
        self.radioVar = tk.StringVar(value=radio_options[0][0])
        
        # create radio buttons
        for name, callback in radio_options:
            self._create_radiobutton(name, callback, padding)

    def _create_radiobutton(self, 
                            text: str, 
                            callback: Callable[[], None], 
                            padding: Tuple[int, int]) -> None:
        ttk.Radiobutton(
            self, text=text, value=text,
            variable=self.radioVar, command=callback
        ).pack(fill='x', padx=padding[0], pady=padding[1])

    def get_selected(self) -> str:
        return self.radioVar.get()


class FileInputFrame(MenuFrame):
    def __init__(self, parent : tk.Widget,
                 padding : Tuple[int, int] = (10, 10),
                 title_font : Tuple[str, int] = ('Arial', 12)):
        pad = (10, 5)
        super().__init__(parent,
                         menu_title="File Input",
                         padding=padding,
                         title_font=title_font)

        self.file_path = tk.StringVar()
        self.file_path.set("")

        self.file_entry = ttk.Entry(self, textvariable=self.file_path)
        self.file_entry.pack(fill='x', padx=pad[0], pady=pad[1])

        self.file_button = ttk.Button(self, text="Browse", 
                                      command=self._browse_file)
        self.file_button.pack(fill='x', padx=pad[0], pady=pad[1])

    def _browse_file(self):
        file_path = filedialog.askopenfilename()
        if file_path:
            self.file_path.set(file_path)
            self.file_entry.xview_moveto(1)

    def get_file_path(self) -> str:
        return self.file_path.get()

    def deacitvate(self):
        self.file_button.config(state='disabled')
        self.file_entry.config(state='disabled')

    def activate(self):
        self.file_button.config(state='normal')
        self.file_entry.config(state='normal')


class TextInputFrame(MenuFrame):
    def __init__(self, parent : tk.Widget,
                 padding : Tuple[int, int] = (10, 10),
                 title_font : Tuple[str, int] = ('Arial', 12)):
        super().__init__(parent, menu_title="Text Input", 
                         padding=padding, title_font=title_font)

        self.text = scrolledtext.ScrolledText(self, width=30, height=10)
        self.text.pack(fill='both', 
                       padx=padding[0], pady=padding[1], 
                       expand=True)

    def get_text(self) -> str:
        return self.text.get(1.0, tk.END)
    
    def activate(self):
        self.text.config(state='normal')
        self.text.config(bg='white')

    def deacitvate(self):
        self.text.config(state='disabled')
        self.text.config(bg='lightgray')


class MatrixInputFrame(MenuFrame):
    def __init__(self, parent : tk.Widget):
        pad = (10, 5)
        super().__init__(parent, menu_title="Equation input", padding=pad)

        radio_options = (
            ("File", self._activate_file_input), 
            ("Text", self._activate_text_input)
        )

        self.src_selection = RadioFrame(self, 
                                        title="Source type", 
                                        radio_options=radio_options, 
                                        padding=pad, 
                                        title_font=('Arial', 10))
        self.src_selection.pack(fill='both', padx=pad[0], pady=pad[1])

        self.file_input_frame = FileInputFrame(self, pad, ('Arial', 10))
        self.file_input_frame.pack(fill='both', padx=pad[0], pady=pad[1])

        self.text_input_frame = TextInputFrame(self, pad, ('Arial', 10))
        self.text_input_frame.pack(fill='both', padx=pad[0], pady=pad[1],
                                   expand=True)

        self._activate_file_input()

    def _activate_file_input(self):
        self.file_input_frame.activate()
        self.text_input_frame.deacitvate()

    def _activate_text_input(self):
        self.text_input_frame.activate()
        self.file_input_frame.deacitvate()

    def get_raw_input(self) -> str:
        selected_mode = self.src_selection.get_selected()
        if selected_mode == "File":
            return self._get_file_input()
        elif selected_mode == "Text":
            return self._get_text_input()
        else:
            raise ValueError("Invalid source type.")
        
    def _get_file_input(self) -> str:
        file_path = self.file_input_frame.get_file_path()
        try:
            with open(file_path, "r", encoding='utf8') as file:
                content = file.read()
                return content
        except FileNotFoundError:
            raise FileNotFoundError(f'File "{file_path}" not found.')

    def _get_text_input(self) -> str:
        return self.text_input_frame.get_text()


class EquationResultFrame(MenuFrame):
    def __init__(self, parent : tk.Widget):
        super().__init__(parent, menu_title="Equation Result")

        self._res_area = scrolledtext.ScrolledText(self, width=30, height=10)
        self._res_area.pack(fill='both', padx=10, pady=10, expand=True)
        self._res_area.config(state='disabled')

    def set_result(self, result : str):
        self._enable_result_field()
        self._res_area.delete(1.0, tk.END)
        self._res_area.insert(tk.END, result)
        self._disable_result_field()

    def _enable_result_field(self):
        self._res_area.config(state='normal')

    def _disable_result_field(self):
        self._res_area.config(state='disabled')


class ConfigFrame(MenuFrame):
    def __init__(self, 
                 parent : tk.Widget, 
                 on_run : Callable[[int, LibraryEnum], None],
                 padding : Tuple[int, int] = (10, 10),
                 title_font : Tuple[str, int] = ('Arial', 12)):
        super().__init__(parent, menu_title="Configuration", 
                         padding=padding, title_font=title_font)

        self._lib_names = ["C", "ASM"]

        self._library_selection = RadioFrame(self, title="Select library:",
            radio_options=[
                (name, lambda: None) for name in self._lib_names
            ]
        )
        self._library_selection.pack(fill='both', padx=10, pady=10)


        thread_num_frame = ttk.Frame(self)
        thread_num_frame.pack(fill='both', padx=10, pady=10)

        thr_num_label = ttk.Label(thread_num_frame, text="Number of threads:")
        thr_num_label.pack(side='left', padx=10, pady=10)

        validation = lambda x: x == "" or (x.isdigit() and 1 <= int(x) <= 65)
        self.thr_num_spinner = ttk.Spinbox(
            thread_num_frame,
            from_=1,
            to=64,
            validate='key',
            validatecommand=(self.register(validation), '%P')
        )
        self.thr_num_spinner.insert(0, 1)
        self.thr_num_spinner.pack(side='left',fill='x', padx=10, pady=10)

        self._on_run = on_run
        runButton = ttk.Button(self, text="Run", 
                               command=self._run_clicked)
        runButton.pack(side='bottom',fill='x', padx=10, pady=10)


    def _get_num_threads(self) -> int:
        return self.thr_num_spinner.get()
    
    def _get_library(self) -> LibraryEnum:
        selected = self._library_selection.get_selected()
        if selected == "C":
            return LibraryEnum.C_LIB
        elif selected == "ASM":
            return LibraryEnum.ASM_LIB
        else:
            raise ValueError("Invalid library selected.")
        

    def _run_clicked(self):
        num_threads = self._get_num_threads()
        
        if not num_threads.isdigit():
            return

        selected_library = self._get_library()
        self._on_run(num_threads, selected_library)


class MainApp(tk.Tk):
    def __init__ (self, title : str, minSize : Tuple[int, int] = (200, 100)):
        super().__init__()
        self.title(title)
        self.minsize(minSize[0], minSize[1])
        self.generate_widgets()
        
    def generate_widgets(self):
        pad_x = 10
        pad_y = 10
        self._input_frame = MatrixInputFrame(self)
        self._input_frame.pack(side = 'left', fill = 'both',
                               expand = True, padx=pad_x, pady=pad_y)

        self._result_frame = EquationResultFrame(self)
        self._result_frame.pack(side = 'left', fill = 'both',
                                expand = True, padx=pad_x, pady=pad_y)

        self._config_frame = ConfigFrame(self, lambda x, y: self._run(x, y))
        self._config_frame.pack(side = 'left', fill = 'both',
                                expand = True, padx=pad_x, pady=pad_y)

    def _run(self, num_threads : int, library : LibraryEnum):
        raw_equations : str
        try :
            raw_equations  = self._input_frame.get_raw_input()
        except FileNotFoundError as e:
            messagebox.showerror("Error", e)
            return

        equations = []
        try:
            equations = parse_linear_equations(raw_equations)
        except ValueError as e:
            messagebox.showerror("Error", str(e))
            return
        
        eq_matrix, var = equations_to_matrix(equations)
        if len(var) < 2:
            self._result_frame.set_result(var[0] + " = " + str(eq_matrix[0][-1]))


if __name__ == "__main__":
    if sys.executable.endswith("python.exe"):
        subprocess.run([sys.executable.replace("python.exe", "pythonw.exe"), *sys.argv])

    app = MainApp("Linear equation system solver", (600, 400))
    app.mainloop()