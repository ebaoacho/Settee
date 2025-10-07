from django.contrib import admin
from django.urls import path
from settee_app.views import register_user, login_user, upload_user_image, recommended_users, like_user, get_user_profile, popular_users, recent_users, matched_users, send_message, get_messages, get_available_dates,  update_available_dates, get_selected_areas, update_selected_areas, update_match_multiple, update_user_profile, health_check, serve_image, delete_account, block_user, report_user, admin_issue_token, admin_list_images_for_user, admin_delete_image, admin_users_by_reports, admin_ban_user, admin_user_ids, user_tickets, exchange_ticket, use_ticket, get_user_entitlements, liked_users, change_email, change_phone, toggle_reviewed, admin_reports_list, admin_report_mark_read, admin_user_reports_read_all, upload_admin_user_image, serve_kyc_image, admin_kyc_list_images_for_user, admin_kyc_delete_image, admin_kyc_toggle_reviewed, admin_kyc_delete_user, received_likes, start_double_match, invite_to_conversation, list_conversations_for_user, send_message_to_conversation, get_conversation_messages, get_unread_matches, match, update_read_match, add_settee_points
from django.conf import settings
from django.conf.urls.static import static

urlpatterns = [
    path('register/', register_user, name='register_user'),
    path('login/', login_user, name='login_user'),
    path('upload-image/', upload_user_image, name='upload_user_image'),
    path('recommended-users/<str:user_id>/', recommended_users, name='recommended_users'),
    path('like/', like_user, name='like_user'),
    path('likes/received/<str:user_id>/', received_likes, name='received_likes'),
    path('get-profile/<str:user_id>/', get_user_profile, name='get_user_profile'),
    path('popular-users/<str:current_user_id>/', popular_users, name='popular_users'),
    path('recent-users/<str:current_user_id>/', recent_users, name='recent_users'),
    path('matched-users/<str:current_user_id>/', matched_users, name='matched_users'),
    path('unread-matches/<str:user_id>/', get_unread_matches, name='get_unread_matches'),
    path('match/', match, name='match'),
    path('match/<str:user_id>/<str:other_id>/read/', update_read_match, name='update_read_match'),
    path('messages/send/', send_message, name='send_message'),
    path('messages/<str:user1_id>/<str:user2_id>/', get_messages, name='get_messages'),
    path('user-profile/<str:user_id>/', get_available_dates, name='get_available_dates'),
    path('user-profile/<str:user_id>/update-available-dates/', update_available_dates, name='update_available_dates'),
    path('user-profile/<str:user_id>/areas/', get_selected_areas, name='get_selected_areas'),
    path('user-profile/<str:user_id>/update-areas/', update_selected_areas, name='update_selected_areas'),
    path('user-profile/<str:user_id>/update-match-multiple/', update_match_multiple, name='update_match_multiple'),
    path('add_settee_points/', add_settee_points, name='add_settee_points'),
    path('update-profile/<str:user_id>/', update_user_profile, name='update_user_profile'),
    path('health/', health_check, name='health_check'),
    path('admin/images/<str:user_id>/<str:filename>/reviewed/', toggle_reviewed, name='toggle_reviewed'),
    path('images/<str:user_id>/<str:filename>', serve_image, name='serve_image'),
    path('users/<str:user_id>/delete/', delete_account, name='delete_account'),
    path('block/', block_user, name='block_user'),
    path('report/', report_user, name='report_user'),
    path('admin/simple-token/', admin_issue_token, name='admin_issue_token'),
    path('admin/images/<str:user_id>/', admin_list_images_for_user, name='admin_list_images_for_user'),
    path('admin/images/<str:user_id>/<str:filename>', admin_delete_image, name='admin_delete_image'),
    path('admin/users/reports/', admin_users_by_reports, name='admin_users_by_reports'),
    # path('admin/messages/<str:user_a>/<str:user_b>/', admin_messages_between, name='admin_messages_between'),
    path('admin/ban/', admin_ban_user, name='admin_ban_user'),
    path('admin/users/ids/', admin_user_ids, name='admin_user_ids'),
    path('users/<str:user_id>/tickets/', user_tickets, name='user_tickets'),
    path('users/<str:user_id>/tickets/exchange/', exchange_ticket, name='exchange_ticket'),
    path('users/<str:user_id>/tickets/<int:ticket_id>/use/', use_ticket, name='use_ticket'),
    path('users/<str:user_id>/entitlements/', get_user_entitlements, name='get_user_entitlements'),
    path('liked-users/<str:current_user_id>/', liked_users, name='liked_users'),
    path('users/<str:user_id>/email/change/', change_email, name='change_email'),
    path('users/<str:user_id>/phone/change/', change_phone, name='change_phone'),
    path('admin/users/reports/', admin_users_by_reports, name='admin_users_by_reports'),
    path('admin/reports/', admin_reports_list, name='admin_reports_list'),
    path('admin/reports/<int:report_id>/read/', admin_report_mark_read, name='admin_report_mark_read'),
    path('admin/users/<str:user_id>/reports/read_all/', admin_user_reports_read_all, name='admin_user_reports_read_all'),
    path('api/admin/upload_user_image/', upload_admin_user_image, name='upload_admin_user_image'),
    path('conversations/user/<str:user_id>/', list_conversations_for_user, name='list_conversations'),
    path('double-match/start/', start_double_match, name='start_double_match'),
    path('double-match/invite/', invite_to_conversation, name='invite_to_conversation'),
    path('conversations/<int:conversation_id>/messages/', get_conversation_messages, name='get_conversation_messages'),
    path('conversations/<int:conversation_id>/messages/send/', send_message_to_conversation, name='send_message_to_conversation'),

    path('images/admin/<str:user_id>/<str:filename>', serve_kyc_image, name='serve_kyc_image'),

    # KYC 一覧/操作（FS直読み版）
    path('admin/kyc/images/<str:user_id>/', admin_kyc_list_images_for_user, name='admin_kyc_list_images_for_user'),
    path('admin/kyc/images/<str:user_id>/<str:filename>', admin_kyc_delete_image, name='admin_kyc_delete_image'),
    path('admin/kyc/images/<str:user_id>/<str:filename>/reviewed/', admin_kyc_toggle_reviewed, name='admin_kyc_toggle_reviewed'),

    # KYC タブからの管理者削除
    path('admin/kyc/users/<str:user_id>/delete/', admin_kyc_delete_user, name='admin_kyc_delete_user'),
]

urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)