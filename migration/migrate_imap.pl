#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;

# Путь к бинарнику imapsync.
my $IMAPSYNC_BIN = 'imapsync'; 

my ($source_server, $dest_server, $file, $max_age, $dest_domain, $src_domain, $nossl, $help);

GetOptions(
    "source=s"      => \$source_server,
    "dest=s"        => \$dest_server,
    "file=s"        => \$file,
    "age=i"         => \$max_age,
    "dest-domain=s" => \$dest_domain,
    "src-domain=s"  => \$src_domain,
    "nossl"         => \$nossl,
    "help"          => \$help,
) or die "Ошибка в аргументах командной строки\n";

if ($help || !$source_server || !$dest_server || !$file) {
    print "Использование: $0 --source <src_host> --dest <dst_host> --file <users_file> [--age <days>] [--dest-domain <domain.com>] [--src-domain <domain.com>] [--nossl]\n";
    exit 1;
}

open(my $fh, '<', $file) or die "Не удалось открыть файл $file: $!\n";

while (my $line = <$fh>) {
    chomp $line;
    
    # Пропускаем пустые строки и комментарии
    next if $line =~ /^\s*$/ || $line =~ /^#/;
    next if ($line =~ /^email\|/);

    # Формат: email|password|displayName|aliases|quota|active|attributes
    my @fields = split(/\|/, $line);
    my $email    = $fields[0];
    my $password = $fields[1];
    
    unless (defined $email && defined $password) {
        warn "Пропущена строка с неверным форматом: $line\n";
        next;
    }
    
    # --- Логика формирования EMAIL ИСТОЧНИКА ---
    my $src_email = $email;
    if (defined $src_domain) {
        my ($local_part) = split(/@/, $email);
        $src_email = $local_part . '@' . $src_domain;
    }
    
    # --- Логика формирования EMAIL ПОЛУЧАТЕЛЯ ---
    my $dest_email = $email;
    if (defined $dest_domain) {
        # Жесткая замена: заменяем весь домен на указанный
        my ($local_part) = split(/@/, $email);
        $dest_email = $local_part . '@' . $dest_domain;
    }
    
    print "=" x 60 . "\n";
    print "Обработка: $src_email -> $dest_email\n";
    
    # Безопасная передача паролей через переменные окружения (локально для итерации цикла)
    local $ENV{IMAPSYNC_PASSWORD1} = $password;
    local $ENV{IMAPSYNC_PASSWORD2} = $password;
    
    # Формируем команду для imapsync
    my @cmd = (
        $IMAPSYNC_BIN,
        '--host1', $source_server,
        '--user1', $src_email,
        '--host2', $dest_server,
        '--user2', $dest_email,
        '--useuid',       # Критически важно: синхронизация по UID (защита от дублей при обрывах)
        '--addheader',    # Добавляет Message-Id для папок Sent/Drafts
    );
    
    # SSL по умолчанию включен.
    unless ($nossl) {
        push @cmd, '--ssl1', '--ssl2';
    }
    
    # Опциональный фильтр по возрасту писем (в днях)
    if (defined $max_age && $max_age > 0) {
        push @cmd, '--maxage', $max_age;
    }
    
    # Запуск
    print "Выполняется: " . join(" ", @cmd) . "\n";
    my $exit_code = system(@cmd);

    # Обработка кода завершения
    if ($exit_code == -1) {
        print "Ошибка запуска imapsync: $!\n";
    } elsif ($exit_code & 127) {
        printf "Процесс imapsync завершился с сигналом %d\n", ($exit_code & 127);
    } else {
        my $ret = $exit_code >> 8;
        if ($ret == 0) {
            print "✅ Успешно синхронизировано.\n";
        } else {
            print "❌ imapsync завершился с кодом ошибки: $ret\n";
        }
    }
}

close($fh);
print "=" x 60 . "\n";
print "Миграция завершена.\n";
