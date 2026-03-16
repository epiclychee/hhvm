/*
   +----------------------------------------------------------------------+
   | HipHop for PHP                                                       |
   +----------------------------------------------------------------------+
   | Copyright (c) 2010-present Facebook, Inc. (http://www.facebook.com)  |
   +----------------------------------------------------------------------+
   | This source file is subject to version 3.01 of the PHP license,      |
   | that is bundled with this package in the file LICENSE, and is        |
   | available through the world-wide-web at the following url:           |
   | http://www.php.net/license/3_01.txt                                  |
   | If you did not receive a copy of the PHP license and are unable to   |
   | obtain it through the world-wide-web, please send a note to          |
   | license@php.net so we can mail you a copy immediately.               |
   +----------------------------------------------------------------------+
*/

#pragma once

#if __has_include(<usdt/usdt.h>)
#include <usdt/usdt.h>
#else

#ifndef USDT
#define USDT(provider, name, ...) do {} while (0)
#endif

#ifndef USDT_WITH_SEMA
#define USDT_WITH_SEMA(provider, name, ...) do {} while (0)
#endif

#ifndef USDT_IS_ACTIVE
#define USDT_IS_ACTIVE(provider, name) false
#endif

#endif
