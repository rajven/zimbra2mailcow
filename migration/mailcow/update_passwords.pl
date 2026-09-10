#!/usr/bin/perl

use strict;
use warnings;
use utf8;

# Настройка кодировки для корректной работы с UTF-8
binmode(STDOUT, ':utf8');

# Проверка наличия аргументов командной строки
my ($file1, $file2, $output_file) = @ARGV;

if (!defined($file1) || !defined($file2) || !defined($output_file)) {
    die "Использование: $0 <исходный_CSV> <файл_паролей> <выходной_файл>\n" .
        "Пример: $0 mailcow_full_20260909.csv mailcow_passwords_20260909.txt result.txt\n";
}

# Проверка существования входных файлов
for my $f ($file1, $file2) {
    if (!-e $f) {
        die "Ошибка: файл '$f' не найден\n";
    }
    if (!-r $f) {
        die "Ошибка: файл '$f' недоступен для чтения\n";
    }
}

# Хеш для хранения новых паролей из второго файла
my %new_passwords;

# Хеш для отслеживания email-адресов, обработанных в первом файле
my %seen_in_file1;

# Массив для хранения email-адресов, которых нет во втором файле
my @missing_in_file2;

# Открытие второго файла для чтения новых паролей
open(my $fh2, '<:utf8', $file2) or do {
    warn "Ошибка: Невозможно открыть файл $file2: $!\n";
    exit 1;
};

# Последовательное чтение строк второго файла
while (my $line = <$fh2>) {
    chomp($line);

    # Пропуск пустых строк
    if ($line eq '') {
        next;
    }

    # Разделение строки по разделителю '=>'
    my @parts = split(/\s*=>\s*/, $line, 2);

    # Обработка ошибок для некорректных строк с продолжением итерации
    if (scalar(@parts) != 2) {
        warn "Предупреждение: Некорректная строка в $file2, пропускаем: $line\n";
        next;
    }

    my $email = $parts[0];
    my $password = $parts[1];

    # Удаление лишних пробелов по краям
    $email =~ s/^\s+|\s+$//g;
    $password =~ s/^\s+|\s+$//g;

    # Сохранение в хеш только если email не пустой
    if ($email ne '') {
        $new_passwords{$email} = $password;
    }
}

close($fh2);

# Открытие первого файла для чтения и результирующего файла для записи
open(my $fh1, '<:utf8', $file1) or do {
    warn "Ошибка: Невозможно открыть файл $file1: $!\n";
    exit 1;
};

open(my $fh_out, '>:utf8', $output_file) or do {
    warn "Ошибка: Невозможно открыть файл $output_file для записи: $!\n";
    exit 1;
};

my $line_number = 0;

# Последовательное чтение строк первого файла
while (my $line = <$fh1>) {
    $line_number++;

    # Сохранение оригинального символа конца строки
    my $line_ending = ($line =~ /(\r?\n)$/) ? $1 : '';
    chomp($line);

    # Пропуск полностью пустых строк с сохранением форматирования
    if ($line eq '') {
        print $fh_out $line_ending;
        next;
    }

    # Проверка на наличие строки заголовка в первой строке
    if ($line_number == 1 && $line =~ /^email\|/i) {
        print $fh_out $line . $line_ending;
        next;
    }

    # Разделение строки по разделителю '|' с сохранением пустых полей в конце
    my @parts = split(/\|/, $line, -1);

    # Обработка ошибок для строк с недостаточным количеством колонок
    if (scalar(@parts) < 2) {
        warn "Предупреждение: Некорректная строка в $file1 на строке $line_number, пропускаем замену: $line\n";
        print $fh_out $line . $line_ending;
        next;
    }

    my $email = $parts[0];

    # Отметка о том, что этот email был встречен в первом файле
    $seen_in_file1{$email} = 1;

    # Проверка наличия нового пароля для данного email
    if (exists $new_passwords{$email}) {
        $parts[1] = $new_passwords{$email};
    }
    else {
        # Добавление в список отсутствующих во втором файле
        push(@missing_in_file2, $email);
    }

    # Замена неопределенных значений на 'NULL' для надежности вывода
    for (my $i = 0; $i < scalar(@parts); $i++) {
        if (!defined($parts[$i])) {
            $parts[$i] = 'NULL';
        }
    }

    # Сборка обновленной строки и запись в файл
    my $updated_line = join('|', @parts);
    print $fh_out $updated_line . $line_ending;
}

close($fh1);
close($fh_out);

# Поиск email-адресов, которые есть во втором файле, но отсутствуют в первом
my @missing_in_file1;

# Использование each для последовательного обхода хеша
while (my ($email, $password) = each %new_passwords) {
    if (!exists $seen_in_file1{$email}) {
        push(@missing_in_file1, $email);
    }
}

# Вывод итогового отчета о расхождениях на экран
print "\n--- Отчет о расхождениях ---\n";

print "Ящики, которые есть в первом файле, но ОТСУТСТВУЮТ во втором (пароль не заменен):\n";
if (scalar(@missing_in_file2) == 0) {
    print "  (нет таких)\n";
}
else {
    for (my $i = 0; $i < scalar(@missing_in_file2); $i++) {
        print "  - $missing_in_file2[$i]\n";
    }
}

print "\nЯщики, которые есть во втором файле, но ОТСУТСТВУЮТ в первом (лишние записи):\n";
if (scalar(@missing_in_file1) == 0) {
    print "  (нет таких)\n";
}
else {
    for (my $i = 0; $i < scalar(@missing_in_file1); $i++) {
        print "  - $missing_in_file1[$i]\n";
    }
}

print "\n✅ Готово! Обновленный файл сохранен как '$output_file'\n";
