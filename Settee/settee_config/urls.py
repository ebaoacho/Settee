from django.contrib import admin
from django.urls import path
from settee_app.views import register_user, login_user, upload_user_image, recommended_users, like_user, get_user_profile, popular_users, recent_users, matched_users, send_message, get_messages, get_available_dates,  update_available_dates, get_selected_areas, update_selected_areas, update_match_multiple, update_user_profile, health_check, serve_image
from django.conf import settings
from django.conf.urls.static import static

urlpatterns = [
    path('register/', register_user, name='register_user'),
    path('login/', login_user, name='login_user'),
    path('upload-image/', upload_user_image, name='upload_user_image'),
    path('recommended-users/<str:user_id>/', recommended_users, name='recommended_users'),
    path('like/', like_user, name='like_user'),
    path('get-profile/<str:user_id>/', get_user_profile, name='get_user_profile'),
    path('popular-users/<str:current_user_id>/', popular_users, name='popular_users'),
    path('recent-users/<str:current_user_id>/', recent_users, name='recent_users'),
    path('matched-users/<str:current_user_id>/', matched_users, name='matched_users'),
    path('messages/send/', send_message, name='send_message'),
    path('messages/<str:user1_id>/<str:user2_id>/', get_messages, name='get_messages'),
    path('user-profile/<str:user_id>/', get_available_dates, name='get_available_dates'),
    path('user-profile/<str:user_id>/update-available-dates/', update_available_dates, name='update_available_dates'),
    path('user-profile/<str:user_id>/areas/', get_selected_areas, name='get_selected_areas'),
    path('user-profile/<str:user_id>/update-areas/', update_selected_areas, name='update_selected_areas'),
    path('user-profile/<str:user_id>/update-match-multiple/', update_match_multiple, name='update_match_multiple'),
    path('update-profile/<str:user_id>/', update_user_profile, name='update_user_profile'),
    path('health/', health_check, name='health_check'),
    path('images/<str:user_id>/<str:filename>', serve_image, name='serve_image'),
]

urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)