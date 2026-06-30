from django.urls import path

from . import views

app_name = 'polls'
urlpatterns = [
    path('', views.IndexView.as_view(), name='index'),
    path('<int:pk>/', views.DetailView.as_view(), name='detail'),
    path('<int:pk>/results/', views.ResultsView.as_view(), name='results'),
    path('<int:question_id>/vote/', views.vote, name='vote'),
    path('sleep', views.i_take_so_long_to_load, name='sleep'),
    path('sleep/<int:how_long>', views.i_take_so_long_to_load, name='sleep'),
    path('error', views.raise_error, name='error'),
    path('ask', views.ask, name='ask'),
]
