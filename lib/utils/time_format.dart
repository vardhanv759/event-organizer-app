import 'package:cloud_firestore/cloud_firestore.dart';

/// Single source of truth for every relative/absolute time label used
/// across the messaging screens, so "2h", "Yesterday", "Active 5m ago"
/// etc. always mean the same thing everywhere instead of being
/// reimplemented slightly differently in each file.
class TimeFormat {
  TimeFormat._();

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// "3:45 PM"
  static String clock(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }

  /// "Jun 12, 2026"
  static String date(DateTime dt) =>
      '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';

  /// "Now" / "5m" / "3h" / "2d" / "12/6" - compact form for list rows.
  static String relativeShort(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}';
  }

  /// "Just now" / "5m ago" / "3h ago" / "2d ago" / "Jun 12, 2026"
  static String relativeLong(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return date(dt);
  }

  /// "Active just now" / "Active 5m ago" / "Active on Jun 12, 2026"
  static String activeAgo(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Active just now';
    if (diff.inHours < 1) return 'Active ${diff.inMinutes}m ago';
    if (diff.inDays < 1) return 'Active ${diff.inHours}h ago';
    if (diff.inDays < 7) return 'Active ${diff.inDays}d ago';
    return 'Active on ${date(dt)}';
  }

  /// "Today" / "Yesterday" / "Jun 12, 2026" — used for date separators.
  static String dayLabel(DateTime dt) {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final dateOnly = DateTime(dt.year, dt.month, dt.day);
    if (dateOnly == DateTime(now.year, now.month, now.day)) return 'Today';
    if (dateOnly == yesterday) return 'Yesterday';
    return date(dt);
  }
}
