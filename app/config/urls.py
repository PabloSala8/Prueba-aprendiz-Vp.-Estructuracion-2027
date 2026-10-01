from django.contrib import admin
from django.urls import path

from portafolios import views

urlpatterns = [
    path('admin/', admin.site.urls),
    path('', views.inicio, name='inicio'),
    path('consultas/', views.consultas, name='consultas'),
    path('portafolio/', views.portafolio, name='portafolio'),
    path('riesgo/', views.riesgo, name='riesgo'),
]
