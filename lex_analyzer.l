%{
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define MAX_ENTRIES 1000
#define MAX_NAME_LEN 100
#define MAX_VALUE_LEN 200
#define MAX_PARAMS_LEN 500
#define MAX_DIMENSIONS_LEN 200

typedef struct {
    char name[MAX_NAME_LEN];
    char type[50];
    char dimensions[MAX_DIMENSIONS_LEN];  // Changed to string to store brackets
    int frequency;
    char return_type[50];
    char parameters[MAX_PARAMS_LEN];
} SymbolEntry;

typedef struct {
    char name[MAX_NAME_LEN];
    int line_number;
    char value[MAX_VALUE_LEN];
    char type[50];
} ConstantEntry;

SymbolEntry symbol_table[MAX_ENTRIES];
ConstantEntry constant_table[MAX_ENTRIES];
int symbol_count = 0;
int constant_count = 0;
int comment_depth = 0;

char current_return_type[50] = "";
char current_parameters[MAX_PARAMS_LEN] = "";
char last_identifier[MAX_NAME_LEN] = "";  // Track last seen identifier
int in_parameter_list = 0;
int paren_count = 0;
int bracket_count = 0;
char temp_dimensions[MAX_DIMENSIONS_LEN] = "";  // To accumulate dimension string
int expecting_assignment = 0;  // Flag to track if we're expecting an assignment

void add_symbol(const char* name, const char* type);
void add_constant(const char* value, const char* type, const char* var_name);
void print_symbol_table();
void print_constant_table();
void update_function_info(const char* name, const char* return_type, const char* parameters);
void reset_context();

void add_symbol(const char* name, const char* type) {
    for(int i = 0; i < symbol_count; i++) {
        if(strcmp(symbol_table[i].name, name) == 0) {
            symbol_table[i].frequency++;
            if(strcmp(type, "function") == 0 || strcmp(type, "array") == 0) {
                strcpy(symbol_table[i].type, type);
            }
            return;
        }
    }
    
    if(symbol_count < MAX_ENTRIES) {
        strcpy(symbol_table[symbol_count].name, name);
        strcpy(symbol_table[symbol_count].type, type);
        strcpy(symbol_table[symbol_count].dimensions, "");  // Initialize to empty string
        symbol_table[symbol_count].frequency = 1;
        strcpy(symbol_table[symbol_count].return_type, "");
        strcpy(symbol_table[symbol_count].parameters, "");
        symbol_count++;
    }
}

void add_constant(const char* value, const char* type, const char* var_name) {
    if(constant_count < MAX_ENTRIES) {
        // Use the variable name if provided, otherwise use the value itself
        if(var_name && strlen(var_name) > 0) {
            strcpy(constant_table[constant_count].name, var_name);
        } else {
            strcpy(constant_table[constant_count].name, value);
        }
        constant_table[constant_count].line_number = yylineno;
        strcpy(constant_table[constant_count].value, value);
        strcpy(constant_table[constant_count].type, type);
        constant_count++;
    }
}

void update_array_dimensions(const char* name, const char* dimensions) {
    for(int i = 0; i < symbol_count; i++) {
        if(strcmp(symbol_table[i].name, name) == 0) {
            strcpy(symbol_table[i].type, "array");
            strcpy(symbol_table[i].dimensions, dimensions);
            break;
        }
    }
}

void update_function_info(const char* name, const char* return_type, const char* parameters) {
    for(int i = 0; i < symbol_count; i++) {
        if(strcmp(symbol_table[i].name, name) == 0) {
            strcpy(symbol_table[i].type, "function");
            if(strlen(return_type) > 0) {
                strcpy(symbol_table[i].return_type, return_type);
            }
            if(strlen(parameters) > 0) {
                strcpy(symbol_table[i].parameters, parameters);
            }
            break;
        }
    }
}

void reset_context() {
    strcpy(current_return_type, "");
    strcpy(current_parameters, "");
    strcpy(temp_dimensions, "");
    strcpy(last_identifier, "");
    in_parameter_list = 0;
    paren_count = 0;
    bracket_count = 0;
    expecting_assignment = 0;
}
%}

%option yylineno
%option noyywrap

%x COMMENT
%x SINGLE_LINE_COMMENT

LETTER          [A-Za-z_]
DIGIT           [0-9]
IDENTIFIER      {LETTER}({LETTER}|{DIGIT})*
KEYWORDS        break|case|continue|default|do|else|enum|for|goto|if|return|sizeof|struct|switch|typedef|union|while
DATA_TYPES      int|float|double|char|void|long|short|unsigned|signed
QUALIFIERS      auto|const|extern|register|static|volatile
PREPROCESSOR    #[ \t]{LETTER}({LETTER}|{DIGIT})
DECIMAL         [1-9]{DIGIT}*|0
OCTAL           0[0-7]+
HEXADECIMAL     0[xX][0-9a-fA-F]+
FLOAT1          {DIGIT}+\.{DIGIT}+([eE][+-]?{DIGIT}+)?[fFlL]?
FLOAT2          {DIGIT}+[eE][+-]?{DIGIT}+[fFlL]?
FLOAT3          \.{DIGIT}+([eE][+-]?{DIGIT}+)?[fFlL]?

%%

{PREPROCESSOR}.*    { 
    printf("Line %d: %s : preprocessor directive\n", yylineno, yytext); 
    reset_context();
}

{DATA_TYPES}        {
    strcpy(current_return_type, yytext);
    printf("Line %d: %s : data type\n", yylineno, yytext);
}

{QUALIFIERS}        {
    printf("Line %d: %s : qualifier\n", yylineno, yytext);
}

{KEYWORDS}          { 
    printf("Line %d: %s : keyword\n", yylineno, yytext); 
    if(strcmp(yytext, "return") == 0 || strcmp(yytext, "if") == 0 || 
       strcmp(yytext, "while") == 0 || strcmp(yytext, "for") == 0) {
        reset_context();
    }
}

{IDENTIFIER}"("     {
    char temp[MAX_NAME_LEN];
    strncpy(temp, yytext, yyleng-1);
    temp[yyleng-1] = '\0';
    add_symbol(temp, "function");
    
    if(strlen(current_return_type) > 0) {
        update_function_info(temp, current_return_type, "");
    }
    
    printf("Line %d: %s : function identifier\n", yylineno, temp);
    
    in_parameter_list = 1;
    paren_count = 1;
    strcpy(current_parameters, "");
    strcpy(last_identifier, "");  // Clear last_identifier for functions
    expecting_assignment = 0;
    
    printf("Line %d: ( : left parenthesis\n", yylineno);
}

{IDENTIFIER}"["     {
    char temp[MAX_NAME_LEN];
    strncpy(temp, yytext, yyleng-1);
    temp[yyleng-1] = '\0';
    add_symbol(temp, "array");
    
    printf("Line %d: %s : array identifier\n", yylineno, temp);
    printf("Line %d: [ : left bracket\n", yylineno);
    
    bracket_count = 1;
    strcpy(temp_dimensions, "[");  // Start building dimension string
    strcpy(last_identifier, temp);  // Store for potential constant assignment
}

{IDENTIFIER}        { 
    add_symbol(yytext, "identifier");
    printf("Line %d: %s : identifier\n", yylineno, yytext); 
    
    // Store the identifier for potential constant association
    strcpy(last_identifier, yytext);
    expecting_assignment = 1;
    
    if(in_parameter_list && paren_count > 0) {
        if(strlen(current_parameters) > 0) {
            strcat(current_parameters, ", ");
        }
        strcat(current_parameters, yytext);
    }
}

{HEXADECIMAL}       { 
    char* var_name = (expecting_assignment && strlen(last_identifier) > 0) ? last_identifier : NULL;
    add_constant(yytext, "hexadecimal", var_name);
    printf("Line %d: %s : hexadecimal constant\n", yylineno, yytext); 
    if(bracket_count > 0) {
        strcat(temp_dimensions, yytext);
    }
    expecting_assignment = 0;  // Reset after processing constant
}

{OCTAL}             { 
    char* var_name = (expecting_assignment && strlen(last_identifier) > 0) ? last_identifier : NULL;
    add_constant(yytext, "octal", var_name);
    printf("Line %d: %s : octal constant\n", yylineno, yytext); 
    if(bracket_count > 0) {
        strcat(temp_dimensions, yytext);
    }
    expecting_assignment = 0;  // Reset after processing constant
}

{DECIMAL}           { 
    char* var_name = (expecting_assignment && strlen(last_identifier) > 0) ? last_identifier : NULL;
    add_constant(yytext, "integer", var_name);
    printf("Line %d: %s : integer constant\n", yylineno, yytext); 
    if(bracket_count > 0) {
        strcat(temp_dimensions, yytext);
    }
    expecting_assignment = 0;  // Reset after processing constant
}

{FLOAT1}|{FLOAT2}|{FLOAT3}  { 
    char* var_name = (expecting_assignment && strlen(last_identifier) > 0) ? last_identifier : NULL;
    add_constant(yytext, "float", var_name);
    printf("Line %d: %s : floating point constant\n", yylineno, yytext); 
    expecting_assignment = 0;  // Reset after processing constant
}

'([^'\\]|\\.)'      { 
    char* var_name = (expecting_assignment && strlen(last_identifier) > 0) ? last_identifier : NULL;
    add_constant(yytext, "character", var_name);
    printf("Line %d: %s : character constant\n", yylineno, yytext); 
    expecting_assignment = 0;  // Reset after processing constant
}

\"([^\"\\]|\\.)*\"  { 
    char* var_name = (expecting_assignment && strlen(last_identifier) > 0) ? last_identifier : NULL;
    add_constant(yytext, "string", var_name);
    printf("Line %d: %s : string constant\n", yylineno, yytext); 
    expecting_assignment = 0;  // Reset after processing constant
}

"/*"                { BEGIN(COMMENT); comment_depth = 1; }
<COMMENT>{
    "/*"            { comment_depth++; }
    "*/"            { 
        if(--comment_depth == 0) {
            BEGIN(INITIAL); 
        }
    }
    .|\n            { }
}

"//"                { BEGIN(SINGLE_LINE_COMMENT); }
<SINGLE_LINE_COMMENT>{
    \n              { BEGIN(INITIAL); }
    .               { }
}

"++"                { printf("Line %d: ++ : arithmetic operator\n", yylineno); expecting_assignment = 0; }
"--"                { printf("Line %d: -- : arithmetic operator\n", yylineno); expecting_assignment = 0; }
"+"                 { printf("Line %d: + : arithmetic operator\n", yylineno); expecting_assignment = 0; }
"-"                 { printf("Line %d: - : arithmetic operator\n", yylineno); expecting_assignment = 0; }
"*"                 { printf("Line %d: * : arithmetic operator\n", yylineno); expecting_assignment = 0; }
"/"                 { printf("Line %d: / : arithmetic operator\n", yylineno); expecting_assignment = 0; }
"%"                 { printf("Line %d: %% : arithmetic operator\n", yylineno); expecting_assignment = 0; }

"<<="               { printf("Line %d: <<= : assignment operator\n", yylineno); }
">>="               { printf("Line %d: >>= : assignment operator\n", yylineno); }
"+="                { printf("Line %d: += : assignment operator\n", yylineno); }
"-="                { printf("Line %d: -= : assignment operator\n", yylineno); }
"*="                { printf("Line %d: *= : assignment operator\n", yylineno); }
"/="                { printf("Line %d: /= : assignment operator\n", yylineno); }
"%="                { printf("Line %d: %= : assignment operator\n", yylineno); }
"&="                { printf("Line %d: &= : assignment operator\n", yylineno); }
"^="                { printf("Line %d: ^= : assignment operator\n", yylineno); }
"|="                { printf("Line %d: |= : assignment operator\n", yylineno); }
"="                 { printf("Line %d: = : assignment operator\n", yylineno); }

"=="                { printf("Line %d: == : relational operator\n", yylineno); expecting_assignment = 0; }
"!="                { printf("Line %d: != : relational operator\n", yylineno); expecting_assignment = 0; }
"<="                { printf("Line %d: <= : relational operator\n", yylineno); expecting_assignment = 0; }
">="                { printf("Line %d: >= : relational operator\n", yylineno); expecting_assignment = 0; }
"<"                 { printf("Line %d: < : relational operator\n", yylineno); expecting_assignment = 0; }
">"                 { printf("Line %d: > : relational operator\n", yylineno); expecting_assignment = 0; }

"&&"                { printf("Line %d: && : logical operator\n", yylineno); expecting_assignment = 0; }
"||"                { printf("Line %d: || : logical operator\n", yylineno); expecting_assignment = 0; }
"!"                 { printf("Line %d: ! : logical operator\n", yylineno); expecting_assignment = 0; }

"<<"                { printf("Line %d: << : bitwise operator\n", yylineno); expecting_assignment = 0; }
">>"                { printf("Line %d: >> : bitwise operator\n", yylineno); expecting_assignment = 0; }
"&"                 { printf("Line %d: & : bitwise operator\n", yylineno); expecting_assignment = 0; }
"|"                 { printf("Line %d: | : bitwise operator\n", yylineno); expecting_assignment = 0; }
"^"                 { printf("Line %d: ^ : bitwise operator\n", yylineno); expecting_assignment = 0; }
"~"                 { printf("Line %d: ~ : bitwise operator\n", yylineno); expecting_assignment = 0; }

"?"                 { printf("Line %d: ? : conditional operator\n", yylineno); expecting_assignment = 0; }
":"                 { printf("Line %d: : : conditional operator\n", yylineno); expecting_assignment = 0; }

"->"                { printf("Line %d: -> : arrow operator\n", yylineno); expecting_assignment = 0; }

"("                 { 
    printf("Line %d: ( : left parenthesis\n", yylineno); 
    if(in_parameter_list) paren_count++;
    expecting_assignment = 0;
}

")"                 { 
    printf("Line %d: ) : right parenthesis\n", yylineno); 
    if(in_parameter_list) {
        paren_count--;
        if(paren_count == 0) {
            in_parameter_list = 0;
            for(int i = symbol_count - 1; i >= 0; i--) {
                if(strcmp(symbol_table[i].type, "function") == 0) {
                    strcpy(symbol_table[i].parameters, current_parameters);
                    break;
                }
            }
        }
    }
    expecting_assignment = 0;
}

"{"                 { 
    printf("Line %d: { : left brace\n", yylineno); 
    reset_context();
}

"}"                 { 
    printf("Line %d: } : right brace\n", yylineno); 
    reset_context();
}

"["                 { 
    printf("Line %d: [ : left bracket\n", yylineno); 
    if(bracket_count > 0) {
        strcat(temp_dimensions, "[");  // Add opening bracket for new dimension
    }
    bracket_count++;
    expecting_assignment = 0;
}

"]"                 { 
    printf("Line %d: ] : right bracket\n", yylineno); 
    strcat(temp_dimensions, "]");  // Add closing bracket
    bracket_count--;
    
    if(bracket_count == 0) {
        // End of array dimensions, update the last array symbol
        for(int i = symbol_count - 1; i >= 0; i--) {
            if(strcmp(symbol_table[i].type, "array") == 0 && 
               strlen(symbol_table[i].dimensions) == 0) {
                strcpy(symbol_table[i].dimensions, temp_dimensions);
                break;
            }
        }
        strcpy(temp_dimensions, "");  // Reset for next array
    }
    expecting_assignment = 0;
}

","                 { 
    printf("Line %d: , : comma\n", yylineno); 
    if(bracket_count > 0) {
        strcat(temp_dimensions, ",");
    }
    if(!in_parameter_list) {
        strcpy(current_return_type, "");
    }
    expecting_assignment = 0;
}

";"                 { 
    printf("Line %d: ; : semicolon\n", yylineno); 
    reset_context();
}

"."                 { printf("Line %d: . : dot\n", yylineno); expecting_assignment = 0; }

[ \t\r\n]+          { }

.                   { 
    printf("ERROR: Line %d: Invalid token '%s'\n", yylineno, yytext); 
    expecting_assignment = 0;
}

%%

void print_symbol_table() {
    printf("\n=== SYMBOL TABLE ===\n");
    printf("%-20s %-12s %-15s %-10s %-12s %-30s\n", 
           "Name", "Type", "Dimensions", "Frequency", "Return Type", "Parameters");
    printf("%-20s %-12s %-15s %-10s %-12s %-30s\n", 
           "----", "----", "----------", "---------", "-----------", "----------");

    for(int i = 0; i < symbol_count; i++) {
        printf("%-20s %-12s %-15s %-10d %-12s %-30s\n",
               symbol_table[i].name,
               symbol_table[i].type,
               symbol_table[i].dimensions[0] ? symbol_table[i].dimensions : "-",
               symbol_table[i].frequency,
               symbol_table[i].return_type[0] ? symbol_table[i].return_type : "-",
               symbol_table[i].parameters[0] ? symbol_table[i].parameters : "-");
    }
}

void print_constant_table() {
    printf("\n=== CONSTANT TABLE ===\n");
    printf("%-25s %-12s %-25s %-15s\n", 
           "Variable Name", "Line Number", "Value", "Type");
    printf("%-25s %-12s %-25s %-15s\n", 
           "-------------", "-----------", "-----", "----");

    for(int i = 0; i < constant_count; i++) {
        printf("%-25s %-12d %-25s %-15s\n",
               constant_table[i].name,
               constant_table[i].line_number,
               constant_table[i].value,
               constant_table[i].type);
    }
}

int main(int argc, char **argv) {
    FILE *input_file = NULL;

    if(argc > 1) {
        input_file = fopen(argv[1], "r");
        if(!input_file) {
            fprintf(stderr, "Error: Cannot open file %s\n", argv[1]);
            return 1;
        }
        yyin = input_file;
    }

    printf("=== LEXICAL ANALYSIS ===\n");
    yylex();

    if(input_file) {
        fclose(input_file);
    }

    print_symbol_table();
    print_constant_table();

    printf("\n=== ANALYSIS SUMMARY ===\n");
    printf("Total symbols: %d\n", symbol_count);
    printf("Total constants: %d\n", constant_count);

    return 0;
}
